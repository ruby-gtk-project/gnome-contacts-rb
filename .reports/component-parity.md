# Component parity — gnome-contacts-rb vs. origin/main

Verified this round by reading both sides of each item (not re-asserting a
prior round's verdict unread), plus a live drive run
(`nix develop --command xvfb-run -a ruby test/drive_main_window.rb` →
`76 of 76 checks passed`, `DRIVE OK`).

## Confirmed working (re-verified this round)

- **Add / edit / delete / undo a contact.** Driven live this round
  (`[1]`–`[18]` range of the drive script); undo restores the deleted
  contact. Matches upstream's `DeleteOperation`/undo toast behaviour.
- **vCard import and export.** Driven live; round-trips every field
  (`test/test_vcard.rb`, 8 tests, all pass this round).
- **Link-suggestion grid, both directions.** Driven live this round for the
  first time with a real UI click path (commit `9b41aef6`): accept merges
  two contacts and is undoable, reject dismisses and the dismissal survives
  selecting the other side of the pair (`dont_suggest_store`). This matches
  `contacts-link-suggestion-grid.vala` + `contacts-link-operation.vala`
  behaviourally, not just structurally.
- **Keyboard shortcuts.** `lib/shortcuts_dialog.rb`'s accelerators
  (`Ctrl+N`, `Ctrl+F`, `Ctrl+I`, `Ctrl+Shift+E`, `Delete`, `F1`,
  `Ctrl+comma`, `Ctrl+Q`, `F10`, `Ctrl+?`) are all registered live via
  `set_accels_for_action` in `lib/main.rb`, not just listed decoratively —
  checked by reading the `WINDOW_ACTIONS`/`APP_ACTIONS` tables and their
  `add_action` call site. Three of the port's ten Overview entries (import,
  export, delete-contact) are not in upstream's own `contacts-shortcuts-
  dialog.blp` at all — upstream only registers `app.help`, `app.show-
  preferences`, `app.quit` as global accels in `contacts-app.vala` and
  leaves the rest as window-local, undocumented-in-the-shortcuts-window
  bindings. The port documenting more of its own real accelerators than
  upstream documents of its own is a surplus, not a gap, but it means the
  shortcuts-dialog text is not a byte-for-byte port of upstream's strings
  (see translation-parity for why that was already a foregone conclusion).

## Confirmed gap: avatar capture via camera

`lib/avatar_selector.rb`'s `camera_button` is wired to the same
`Ashpd::Camera.present?` portal check upstream uses
(`portal.is_camera_present()`), and its sensitivity is driven live and
checked by the drive script (`[43] ashpd reports the real camera presence to
the avatar selector`). **But clicking it does not capture a photo.** The
handler (`report_no_capture`, `lib/avatar_selector.rb:249`) opens an
`Adwaita::AlertDialog` reading "Camera capture isn't supported yet; choose a
file instead." Upstream's equivalent path calls
`portal.access_camera()` followed by `portal.open_pipewire_remote_for_camera()`
and actually streams from the camera into the crop dialog. This is
disclosed candidly in both the code comment and
`.reports/component-inventory.md` — it is not a silently-dropped feature —
but disclosure does not change the parity verdict: **camera-based avatar
capture is 0% ported**, file-picker-based avatar selection is fully ported.
This is a real, user-facing capability gap, not a documentation nit.

## Confirmed gap: first-run setup flow is unverified by any live drive

`lib/setup_window.rb` (the first-run address-book picker,
`$ContactsSetupWindow`) and the account rows it shows via
`lib/accounts_list.rb` are only reachable when `App.new` is constructed with
a non-empty `setup_backends` list. The drive script's `App.new` always
passes none (so the window is legitimately unreachable from that one
configuration), and `test/test_app.rb` only constructs `SetupWindow`
directly off the main loop — not through the real "no backend configured →
app shows setup window → user picks one → main window opens" flow a first
install actually exercises. Per this round's stated gate ("a component no
check exercises is unverified, not done"): **the first-run onboarding path
has zero end-to-end verification**, live or automated. Its unit-level pieces
are tested, the flow that stitches them together is not.

## Narrower, previously-noted gaps re-checked and still present

- `lib/im_service.rb` and `lib/type_combo_row.rb` are exercised only
  indirectly (fixture data fed to the editor in Minitest; never clicked
  through a live IM-field-populate-then-type-picker-select path in the
  drive script). Re-confirmed this round by reading `test/drive_main_window.rb`
  end to end — no step targets either widget by name.
- `lib/crop_dialog.rb`'s actual crop interaction (drag the crop rectangle)
  is not driven live — `test/test_app.rb` exercises it off-screen. The
  dialog opens and closes correctly in the drive, but the crop gesture
  itself is only unit-tested, not interaction-tested.

## Verdict

Not clean. One full feature gap (camera capture), one unverified end-to-end
flow (first-run setup), and two narrower interaction paths exercised only at
the unit level, not through a live click.
