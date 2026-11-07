# Driving the app — findings

## GC-reentrancy abort inside GObject closure callbacks

Running `test/drive_main_window.rb` under `nix develop --command xvfb-run -a
ruby test/drive_main_window.rb` aborted every time, but not at the same
place: one run died in `lib/qr_code_dialog.rb`'s QR-code encoding (an
`Integer#&` inside `rqrcode_core`), another in a plain `String#gsub` in
`lib/vcard.rb`. Both crashes print the same VM message:

```
[BUG] object allocation during garbage collection phase
```

The C-level backtrace in both crashes bottoms out in `glib2.so`'s
`rclosure_marshal_do` / `rclosure_default_g2r_func` — i.e. GLib invoking a
Ruby-side signal handler (every `window.activate_action(...)` the drive
script fires goes through exactly this path) — calling into `rb_protect`,
which lands inside `rb_wb_protected_newobj_of` while the VM is mid-sweep.
This is a GC-safety bug in the `glib2`/`gobject-introspection` binding layer
(a Ruby object got allocated from inside a GObject C closure callback while
GC was already running), not a bug in the application code that happened to
be executing when the sweep landed — the two crash sites share no code path
except "ordinary Ruby running inside a GObject signal callback".

**Confirmed, not assumed:** re-running the exact same steps with `GC.disable`
set at the top of the script completes all 55 (now 59) checks with zero
failures, deterministically, across repeated runs. The port's logic is
correct; the crash is purely a VM/binding interaction. `test/drive_main_window.rb`
now disables GC for the (short, single-purpose) duration of the drive, with
a comment explaining why. This does not loosen, skip or rescue any check —
every assertion still runs and is still strict; it only prevents an
unrelated VM abort from interrupting the run before the checks get to execute.

This is the same class of problem flagged elsewhere in this campaign
(ruby-gnome binding gaps, e.g. Chess-Clock-rb's `add_breakpoint` and
Junction-rb's `Breakpoint` setter both hitting
`TODO: in Ruby -> GIArgument(array/C)[interface(enum)]`), except here the
binding doesn't refuse the call outright — it corrupts VM GC state
intermittently under real signal traffic. Worth tracking upstream in
ruby-gnome/gobject-introspection if this port ever ships for real, since
disabling GC for a long-running desktop app (rather than a short test
script) is not an acceptable fix.

## Drive script coverage

`test/drive_main_window.rb` builds the real `App` (JSON backend, scratch
`XDG_CONFIG_HOME`/`XDG_DATA_HOME`) and drives it through 36 steps / 59
checks / 17 screenshots under `tmp/shots/`. Components exercised, each with
an assertion and a screenshot:

- Empty state (`lib/contact_list.rb`, `lib/contact_pane.rb`)
- Adding contacts and the favourites-first sort (`lib/contact_store.rb`)
- The contact sheet rendering every field (`lib/contact_sheet.rb`)
- The contact editor, structured name included (`lib/contact_editor.rb`,
  `lib/birthday_editor.rb` via its row)
- Renaming through the editor and the save reaching the model and the file
  (`lib/json_backend.rb`)
- Selection mode: chrome swap, marking, bulk-action sensitivity
  (`lib/contact_list.rb`'s selection model)
- Search filtering and the no-results page
- Sort-order switching and the setting persisting (`lib/settings.rb`)
- The QR-code dialog, real encode-and-paint (`lib/qr_code_dialog.rb`)
- The preferences dialog (`lib/preferences_dialog.rb`)
- The shortcuts dialog (`lib/shortcuts_dialog.rb`)
- Export to vCard (`lib/vcard.rb`, `lib/vcard_backend.rb`-shaped path)
- Delete + undo (`lib/operations.rb`)
- The real **ImportDialog** (`lib/import_dialog.rb`) — opened with a real
  file, its preview row read back off the actual widget tree, Import clicked
  to confirm — not just the `import_parsed` callback it eventually calls
- A full reload from disk confirming every field round-trips
  (`lib/contact_store.rb`, `lib/json_backend.rb`)

That is 13 of the 31 `lib/*.rb` files touched directly by name, and several
more indirectly (`lib/operations.rb`, `lib/settings.rb`, `lib/type_set.rb`
via the editor's type rows). Covered only by the Minitest suite
(`test/test_*.rb`, 137 runs / 452 assertions, no display needed), not by this
drive script: `lib/shell_search_provider.rb`, `lib/backend.rb`,
`lib/vcard_backend.rb`'s own class, `lib/type_set.rb`.

### Update: link-suggestion UI now driven live too

A later pass closed the `lib/link_suggestion_grid.rb` / `lib/dont_suggest_store.rb`
gap this report originally listed. The drive now:

- adds two contacts sharing an email, selects one, and asserts the real
  `LinkSuggestionGrid` the running `ContactPane` built appears under the
  sheet (`contact_pane.suggestions_box.child`);
- clicks its **No** button (found by walking the real widget tree — there is
  no direct accessor from the pane to the grid object, only to what it
  built) and asserts the grid disappears, then re-selects the other side of
  the pair and asserts the dismissal was recorded for both directions
  (`DontSuggestStore#may_suggest_link?`'s bidirectional check);
- adds a second pair sharing a phone number, clicks **Yes**, and asserts
  `Operations::LinkOperation` actually ran against the live store: one
  contact disappears, the survivor keeps the shared phone, and gains the
  other side's distinguishing email — and that the link is undoable.

**Found while wiring this up, not assumed:** `Gtk::Button#activate` is a
no-op immediately after a widget is first built into a box that has not yet
had a layout pass (every other `.activate` call in this script targets a
button that has been on screen for a while and works fine). The symptom was
silent — `activate` returned normally, no exception, just no `clicked`
handler run — so the first version of this step reported a false pass by
checking a field the two test contacts already shared before any merge.
Fixed two ways: the suggestion buttons are clicked with `signal_emit('clicked')`
(what a real click delivers regardless of map state) instead of `.activate`,
and the accept-path assertion was changed to check a field that only the
*other* contact had, so a no-op click would actually fail it.

Still not exercised by either suite — genuine gaps, not claimed as covered:

- `lib/setup_window.rb` / `lib/accounts_list.rb` — the first-run address-book
  picker. It only appears when `setup_backends` is non-empty
  (`lib/main.rb:671`'s `setup_needed?`); the drive's `App.new` passes none,
  so the window is legitimately never reachable with one backend configured.
  Needs a second drive (or a dedicated step) that constructs `App` with a
  non-empty `setup_backends` to open this window at all. (`SetupWindow` is
  exercised directly, off the main loop, by `test/test_app.rb`.)
- `lib/avatar.rb`, `lib/avatar_selector.rb`, `lib/editable_avatar.rb`,
  `lib/crop_dialog.rb` — avatar picking/cropping UI. `AvatarSelector` is
  built and its camera-button sensitivity checked live by this drive script;
  `CropDialog` and the file-picker path are exercised directly by
  `test/test_app.rb`, not through a real click here (`Gtk::FileDialog` is
  async and raises on cancel, so it cannot be driven by clicking — see the
  testing skill's traps section).
- `lib/im_service.rb`, `lib/type_combo_row.rb` — IM service lookups and the
  type-picker combo row are only indirectly touched (the editor's IM field is
  populated via fixtures in the Minitest suite, not clicked through here).

## Spec suite

The dev-shell banner's `rspec` command finds nothing to run: `spec/` holds
only `spec_helper.rb` and a `kettle-test` harness README, no actual spec
files. The real suite is Minitest under `test/test_*.rb` (137 runs, 452
assertions, 0 failures, 0 errors, 0 skips this round).
