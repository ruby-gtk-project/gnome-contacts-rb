# gnome-contacts-rb

A Ruby port of [GNOME Contacts](https://gitlab.gnome.org/GNOME/gnome-contacts),
built with the `gtk4` and `adwaita` ruby-gnome bindings.

The `main` branch tracks upstream's Vala sources. This branch (`ruby`) is the
port, written in the declarative memoized-widget house style: every widget is a
memoized method, all styling lives in that method's `tap` block, and `build`
contains only structure and behaviour.

## Running

```sh
bin/gnome-contacts-rb                  # JSON backend (default)
bin/gnome-contacts-rb vcard            # directory-of-vCards backend
bin/gnome-contacts-rb --search ada     # open with a search already filled in
bin/gnome-contacts-rb --email a@b.com  # open showing the contact with this address
bin/gnome-contacts-rb --individual ID  # open showing this contact
bin/gnome-contacts-rb --version
```

## Testing

```sh
rake test                                                     # 129 examples
env -u DISPLAY -u WAYLAND_DISPLAY ruby test/drive_main_window.rb   # 55 checks + screenshots
```

`rake test` covers the model, the store, both backends, the vCard serialiser,
the type sets, the undo stack, the shell search provider, settings persistence
and the live widget tree.

`test/drive_main_window.rb` runs the whole app headlessly — GTK4 renders to an
offscreen surface, so no Xvfb is needed — steps through creating, editing,
searching, sorting, selecting, linking, deleting, undoing, exporting and
importing, and writes a PNG of each state to `tmp/shots/`. **Read the
screenshots.** Three bugs in this port were found by looking at them rather
than by asserting: list rows that kept their old label after the sort order
changed, selection checkboxes that never ticked, and a bottom action bar left
insensitive after leaving selection mode.

## Installing the dependencies

`gtk4` and `adwaita` are native gems. `adwaita` in particular runs a
`pkg-config` dependency check at install time, so libadwaita's *development*
files must be findable:

```sh
PKG_CONFIG_PATH=/path/to/libadwaita-1/lib/pkgconfig gem install adwaita
```

Without it the build fails with a bare `rake failed, exit code 1` even though
the gem itself is pure Ruby — the failure is only the dependency probe.

## What is ported

Everything upstream does that does not require Folks or Evolution Data Server.

| Upstream | Here |
|---|---|
| Contact chunks (alias, avatar, birthday, emails, IM addresses, full name, structured name, nickname, notes, phones, addresses, roles, URLs) | `Contact`, with `TypedValue` / `Role` / `ImAddress` / `StructuredName` / `Avatar` |
| `TypeSet` (general / email / phone) and custom labels | `TypeSet`, same lists, custom labels via `X-GOOGLE-LABEL` |
| `ImService` | `ImService`, same service table |
| Main window, contact sheet, contact editor | `App`, `ContactSheet`, `ContactEditor` |
| Selection mode: export / link / delete marked contacts | `win.select-contacts` and the bulk actions |
| `LinkSuggestionGrid` | `LinkSuggestionGrid`, driven by `ContactStore#link_suggestions_for` |
| `Operation` / `OperationList` with undo | `Operations`, undo surfaced through the toasts and `Ctrl+Z` |
| Editable avatar, avatar selector, crop dialog (`cc-crop-area.c`) | `EditableAvatar`, `AvatarSelector`, `CropDialog` |
| QR code dialog (libqrencode) | `QrCodeDialog` (rqrcode_core + Cairo) |
| Import dialog, preferences dialog, shortcuts dialog, setup window | `ImportDialog`, `PreferencesDialog`, `ShortcutsDialog`, `SetupWindow` |
| `org.gnome.Contacts` GSettings schema | `Settings`, same keys and defaults |
| Shell search provider (`org.gnome.Shell.SearchProvider2`) | `ShellSearchProvider` |
| Command-line options (`--email`, `--individual`, `--search`, `--version`) | same, in `bin/gnome-contacts-rb` |
| EDS / Folks backends | `JsonBackend`, `VCardBackend` |

Where upstream's behaviour depends on Folks specifically, the port keeps the
feature and changes the mechanism:

- **Linking** merges the fields of the selected contacts into the first and
  removes the others, instead of asking Folks to link personas. The operation
  is reversible, so unlinking restores exactly what was there before.
- **Unlinking** reverses the most recent link. Without personas there is no
  recorded seam to split an unlinked contact along, so unlinking a contact that
  was never linked reports that rather than guessing.
- **Settings** are a JSON file under `XDG_CONFIG_HOME` rather than GSettings,
  because a compiled schema would have to be installed system-wide before the
  app could run from a checkout. The keys and defaults are upstream's.
- **The avatar selector** has no camera source: that goes through the XDG
  desktop portal, which has no ruby-gnome binding. Choosing a file and cropping
  it works as upstream does.
- **The preferences dialog** lists the one active address book, since there is
  one backend rather than a set of EDS sources.

## Layout

```
bin/gnome-contacts-rb    Entry point and command-line options
lib/main.rb              App — window, header bars, actions, state machine
lib/contact.rb           Contact model + TypedValue / Role / ImAddress /
                         StructuredName / Avatar
lib/type_set.rb          Per-field type labels and vCard TYPE mappings
lib/im_service.rb        IM service identifiers and display names
lib/contact_store.rb     Backend + ListStore + filter/selection + suggestions
lib/contact_list.rb      Sidebar list view, selection mode, empty states
lib/contact_pane.rb      Right pane: status page / sheet / editor stack
lib/contact_sheet.rb     Read-only contact view
lib/contact_sheet_row.rb One field row on the sheet
lib/contact_editor.rb    Editable contact form
lib/editable_avatar.rb   Avatar with the camera badge
lib/avatar_selector.rb   Stock avatars and "choose a file"
lib/crop_dialog.rb       Square crop area
lib/qr_code_dialog.rb    Contact as a QR code
lib/import_dialog.rb     Import preview
lib/preferences_dialog.rb  Address books and sort order
lib/shortcuts_dialog.rb  Keyboard shortcuts
lib/setup_window.rb      First-run address book picker
lib/link_suggestion_grid.rb  "Is this the same person?" bar
lib/operations.rb        Undoable delete / link / unlink / import
lib/settings.rb          Persisted settings
lib/shell_search_provider.rb  org.gnome.Shell.SearchProvider2
lib/vcard.rb             vCard 4.0 serialiser and parser
test/gtk_driver.rb       Headless UI driver (from the ruby-gtk-testing skill)
test/drive_main_window.rb  End-to-end drive with screenshots
lib/backend.rb           Backend interface
lib/json_backend.rb      Single JSON file
lib/vcard_backend.rb     Directory of .vcf files
```

Contacts live under `$XDG_DATA_HOME/ruby-contacts/`, settings under
`$XDG_CONFIG_HOME/ruby-contacts/`.

## Keyboard shortcuts

| | |
|---|---|
| `Ctrl+N` | New contact |
| `Ctrl+E` | Edit contact |
| `Ctrl+Return` | Save changes |
| `Escape` | Cancel editing, or leave selection mode |
| `Ctrl+F` | Search |
| `Delete` | Delete contact |
| `Ctrl+Z` | Undo |
| `Ctrl+I` | Import vCards |
| `Ctrl+Shift+E` | Export all contacts |
| `Ctrl+,` | Preferences |
| `Ctrl+?` | Keyboard shortcuts |
| `F1` | Help |
| `Ctrl+Q` / `Ctrl+W` | Quit |

## Binding quirks found while porting

These are not guessable from the C or Vala documentation, and each one cost
real debugging time.

**`Gtk::CustomSorter` hands its block raw pointers.** In ruby-gnome 4.3.7 the
comparison block receives GObject addresses as `Integer`s, not the Ruby
objects, so any method call on them raises `NoMethodError`. `Gio::ListStore#sort`
has the same problem; `Gtk::CustomFilter` does *not*. `ContactStore#resort`
therefore sorts in Ruby and writes the order back with `Gio::ListStore#splice`,
which round-trips the objects intact.

**`Adwaita::ApplicationWindow` works, and you want it.** A
`Gtk::ApplicationWindow` draws its own titlebar above your `Adwaita::HeaderBar`s,
so the window ends up with two title bars and two close buttons. The Adwaita
window has no titlebar of its own — but it takes `content=`, not `child=`.
(`Adwaita::Application` is still broken; the application object stays a
`Gtk::Application`.)

**Require ruby-gnome before `minitest/autorun`.** Both register an `at_exit`
hook and those run last-in-first-out, so requiring ruby-gnome *second* makes its
callback-bridge teardown run *before* minitest runs a single test. Signals then
silently stop firing: `signal_connect` still returns a handler id, but GLib
reports "no handlers connected" and every UI test passes vacuously. `in_app` in
the test suite asserts that its body actually ran, so this cannot recur silently.

**`Gtk::Widget#visible?` is `gtk_widget_is_visible()`**, which is false whenever
any ancestor is hidden. To assert on the flag your own code set, read the
`visible` property instead.

**Endless methods and trailing `if`.** `def foo = bar if @x` parses as
`(def foo = bar) if @x`, so the method is conditionally *defined* rather than
conditionally executed. Parenthesise the body.

**Constants inside a `Data.define` block bind to the enclosing scope.**
`Data.define(:a) { FOO = 1 }` defines `Object::FOO`, not `MyData::FOO`. Reopen
the class with `class MyData` instead.

**`Adwaita::ShortcutsItem` takes positional arguments** — even though the error
a no-argument `new` raises advertises the signatures as
`initialize(title: utf8, accelerator: utf8)`. Keywords fail; positional works.

**There is no `GLib::Markup`.** Escape Pango markup by hand.

**`GLib::Variant.new` cannot build `a{sv}` or a reply tuple.** It raises
`NotImplementedError` for a dictionary. `GLib::Variant.parse(text, type)` builds
both, which is how the search provider assembles its D-Bus replies.

**`Gio::DBusNodeInfo#interfaces` returns unusable strings.** Use
`#lookup_interface(name)` to get the `Gio::DBusInterfaceInfo` you need to
register an object.

**Action parameters arrive unwrapped.** A `GLib::VariantType`-parameterised
`Gio::SimpleAction` hands its handler a Ruby `String`, not a `GLib::Variant`, so
there is no `get_string` to call.

**`Adwaita::NavigationPage.new(child, title)`** takes positional arguments only,
so the child widget must exist before the page.

**`Gtk::IconPaintable#file` is nil for icons in a gresource.** To rasterise one,
go through `Gtk::Snapshot` and draw the resulting `Gsk::RenderNode` onto a Cairo
context.

**An exception raised inside a GTK signal handler can take the process down**
with SIGSEGV rather than surfacing as a Ruby error. When a test crashes instead
of failing, look for a `NoMethodError` inside a handler.

**A Contact removed from a `Gio::ListStore` can become a dangling pointer.**
The store's reference was what kept it alive, and the Ruby wrapper does not
hold one of its own, so re-inserting a removed object or reading one back from
a model afterwards segfaults. `ContactStore` therefore keeps its own ordered
Array of every live contact, routes every read through that, and records undo
information as plain hashes rather than objects.

**`Gtk::ListView` moves rows rather than rebinding them.** When a splice
reorders the *same* objects, the existing row widgets are repositioned and the
factory's `bind` never runs again — so any label computed from something other
than the item itself goes stale. Handing the list view a fresh factory forces a
rebuild. For per-row state that changes without a rebind (the selection tick),
bind the property instead: `item.bind_property('selected', checkbox, 'active',
:sync_create)`.

**GTK4 has no `Gtk.main_iteration`.** Pump `GLib::MainContext.default` with
`#pending?` and `#iteration(false)` when a test needs layout to settle.
