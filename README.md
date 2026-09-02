# gnome-contacts-rb

A Ruby port of [GNOME Contacts](https://gitlab.gnome.org/GNOME/gnome-contacts),
built with the `gtk4` and `adwaita` ruby-gnome bindings.

The `main` branch tracks upstream's Vala sources. This branch (`ruby`) is the
port, written in the declarative memoized-widget house style: every widget is a
memoized method, all styling lives in that method's `tap` block, and `build`
contains only structure and behaviour.

## Running

```sh
bin/gnome-contacts-rb          # JSON backend (default)
bin/gnome-contacts-rb vcard    # directory-of-vCards backend
```

## Testing

```sh
rake test
```

68 examples covering the model, the store, both backends, the vCard
serialiser, and the live widget tree. The UI tests build the real window and
drive it through its `GAction`s; they skip themselves when no display is
available, and never map a window on screen.

## Installing the dependencies

`gtk4` and `adwaita` are native gems. `adwaita` in particular runs a
`pkg-config` dependency check at install time, so libadwaita's *development*
files must be findable:

```sh
PKG_CONFIG_PATH=/path/to/libadwaita-1/lib/pkgconfig gem install adwaita
```

Without it the build fails with a bare `rake failed, exit code 1` even though
the gem itself is pure Ruby — the failure is only the dependency probe.

## What the port keeps, and what it drops

Upstream is ~75 Vala files carrying a lot of machinery that exists to satisfy
Folks and Evolution Data Server. Following the porting methodology, that
machinery is dropped rather than reproduced:

| Upstream | Here | Why |
|---|---|---|
| `Folks.IndividualAggregator` | `ContactStore` | One backend at a time; no persona merging |
| 15+ `*-chunk.vala` classes | `TypedValue` / `Role` | Chunks exist so Folks always sees valid data mid-edit |
| `Operation` subclasses + undo stack | plain store methods | Those wrap async D-Bus calls; file I/O is synchronous |
| EDS / Folks backends | `JsonBackend`, `VCardBackend` | Plain files, no D-Bus |
| Shell search provider, QR codes, avatar cropping | — | Out of scope for the port |

What is kept is the shape of the app: the navigation split view, the contact
sheet and editor, multi-value fields with type labels, search, favourites,
delete-with-undo, and vCard import/export.

### Multi-value fields

The style guide starts data models at plain string attributes. This port keeps
arrays of `TypedValue`, because upstream's contacts genuinely have several
emails, phones, addresses and roles each with a `Work`/`Home` label, and
flattening them to single strings would lose data the sheet and the editor both
already display. The complexity stops there: `TypedValue` is a two-field
`Data`, not a class hierarchy.

## Layout

```
bin/gnome-contacts-rb   Entry point
lib/main.rb             App — window, header bars, actions, state machine
lib/contact.rb          Contact model (GLib::Object) + TypedValue / Role
lib/contact_store.rb    Backend + ListStore + filter/selection chain
lib/contact_list.rb     Sidebar list view, empty states
lib/contact_pane.rb     Right pane: status page / sheet / editor stack
lib/contact_sheet.rb    Read-only contact view
lib/contact_sheet_row.rb  One field row on the sheet
lib/contact_editor.rb   Editable contact form
lib/vcard.rb            vCard 4.0 serialiser and parser
lib/backend.rb          Backend interface
lib/json_backend.rb     Single JSON file
lib/vcard_backend.rb    Directory of .vcf files
```

Data lives under `$XDG_DATA_HOME/ruby-contacts/`.

## Keyboard shortcuts

| | |
|---|---|
| `Ctrl+N` | New contact |
| `Ctrl+E` | Edit contact |
| `Ctrl+F` | Search |
| `Delete` | Delete contact |
| `Ctrl+I` | Import vCards |
| `Ctrl+Shift+E` | Export all contacts |
| `Escape` | Cancel editing |
| `F1` | About |
| `Ctrl+Q` / `Ctrl+W` | Quit |

## Binding quirks found while porting

These are not guessable from the C or Vala documentation, and each one cost
real debugging time:

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

**`Adwaita::NavigationPage.new(child, title)`** takes positional arguments only,
so the child widget must exist before the page.
