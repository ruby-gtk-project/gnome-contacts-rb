# Component inventory — gnome-contacts-rb vs. upstream (GNOME Contacts)

Surveyed against `origin/main` (Vala + blueprint upstream). This is a
file-level map: for widget/CSS/signal-level detail on any one row, run the
`component-identification` skill's scan against that upstream file and the
corresponding `lib/*.rb`.

Legend for **Status**: `done` = a `lib/*.rb` exists and names this upstream
file as its source in its header comment; `partial` = exists but the header
or code shows acknowledged gaps; `stub` = file exists but is scaffold
placeholder, not the port; `missing` = no `lib/*.rb` yet.

## Windows

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `src/contacts-app.vala` | `lib/main.rb` (`App`) | application class | done |
| `src/contacts-main-window.vala` + `data/ui/contacts-main-window.blp` | `lib/main.rb` (`App`) | main window | done |
| `src/contacts-setup-window.vala` + `data/ui/contacts-setup-window.blp` | `lib/setup_window.rb` | first-run wizard window | done |
| `src/contacts-ui-state.vala` | `lib/main.rb` (`NORMAL`/`SHOWING`/`CREATING`/`UPDATING` constants) | UI-state enum | done (folded in) |
| — (scaffold) | ~~`lib/gnome_contacts/application.rb`, `lib/gnome_contacts.rb`, `exe/gnome-contacts`~~ | leftover scaffold stub app (status-page placeholder) | **removed** — it was dead code, unreachable from the real entry point (`exe/gnome-contacts-rb`, which boots `App` from `lib/main.rb`), and its presence in `exe/` made the flake's launcher auto-detection (`builtins.head (builtins.attrNames (builtins.readDir ./exe))`) pick the wrong binary |

## Pages / panes

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `src/contacts-contact-list.vala` | `lib/contact_list.rb` | sidebar list page | done |
| `src/contacts-contact-pane.vala` + `data/ui/contacts-contact-pane.blp` | `lib/contact_pane.rb` | detail pane (sheet/editor switch) | done |
| `src/contacts-contact-sheet.vala` | `lib/contact_sheet.rb` | read-only contact sheet | done |
| `src/contacts-contact-sheet-row.vala` + `data/ui/contacts-contact-sheet-row.blp` | `lib/contact_sheet_row.rb` | one field row on the sheet | done |
| `src/contacts-contact-editor.vala` | `lib/contact_editor.rb` | in-place edit form | done |
| `src/contacts-contact-editor.vala` (`BirthdayEditor` inner class) + `data/ui/contacts-birthday-editor.blp` | `lib/birthday_editor.rb` | birthday-entry sub-dialog | done |
| `src/contacts-link-suggestion-grid.vala` + `data/ui/contacts-link-suggestion-grid.blp` | `lib/link_suggestion_grid.rb` | "possible duplicate" suggestion bar | done |

## Dialogs

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `src/contacts-avatar-selector.vala` + `data/ui/contacts-avatar-selector.blp` | `lib/avatar_selector.rb` | avatar-picker dialog | partial — no camera/portal source (no XDG portal binding in ruby-gnome; noted in file header) |
| `src/contacts-crop-dialog.vala` + `data/ui/contacts-crop-dialog.blp` + `src/cc-crop-area.c`/`.h` | `lib/crop_dialog.rb` | square-crop dialog | done |
| `src/contacts-import-dialog.vala` + `data/ui/contacts-import-dialog.blp` | `lib/import_dialog.rb` | vCard import preview dialog | done |
| `src/contacts-preferences-window.vala` + `data/ui/contacts-preferences-window.blp` | `lib/preferences_dialog.rb` | address-book preferences dialog | partial — upstream lists live EDS sources with enable/disable toggles; port reports the single active backend only, by design (no EDS) |
| `src/contacts-qr-code-dialog.vala` | `lib/qr_code_dialog.rb` | vCard-as-QR dialog | partial — upstream uses libqrencode (no Ruby binding); port uses `rqrcode_core` instead |
| `src/contacts-shortcuts-dialog.vala`(none found; shortcuts come from blueprint) + `data/ui/contacts-shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | keyboard-shortcuts window | done |
| `src/contacts-editable-avatar.vala` + `data/ui/contacts-editable-avatar.blp` | `lib/editable_avatar.rb` | avatar-with-camera-badge widget (opens `AvatarSelector`) | done |

## Rows / small widgets

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `src/contacts-avatar.vala` | `lib/avatar.rb` (`ContactAvatar`) | avatar display widget | done (renamed to avoid clash with `Avatar` already used for photo data in `contact.rb`) |
| `src/contacts-accounts-list.vala` | `lib/accounts_list.rb` | address-book picker list (used by setup window) | done |
| `src/contacts-type-combo.vala` | `lib/type_combo_row.rb` | type-label combo row (Home/Work/Mobile/custom) | done |

## Menus / actions / shortcuts

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `ACTION_ENTRIES` in `src/contacts-app.vala` | `lib/main.rb` (`WINDOW_ACTIONS`) | window actions + accelerators | done |
| `data/ui/contacts-shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | shortcuts window content | done |
| App menu / primary menu in `contacts-main-window.blp` | `lib/main.rb` | header-bar menu | needs confirmation against blueprint menu model (not yet scanned at widget level) |

## Data model / IO (non-UI, but required for component parity)

| Upstream | → lib/ | Kind | Status |
|---|---|---|---|
| `src/core/contacts-contact.vala` + all `src/core/contacts-*-chunk.vala` (addresses, alias, avatar, bin, birthday, email-addresses, full-name, im-addresses, nickname, notes, phones, roles, structured-name, urls) | `lib/contact.rb` | contact data model (`TypedValue` + fields) | done — collapsed Folks per-field `Chunk` classes into one plain Ruby object, since there is no Folks binding |
| `src/core/contacts-type-descriptor.vala`, `src/core/contacts-type-set.vala`, `src/core/contacts-vcard-type-mapping.vala` | `lib/type_set.rb` | field-type label set + vCard TYPE mapping | done |
| `src/contacts-im-service.vala` | `lib/im_service.rb` | IM-service-id → display-name map | done |
| `src/io/contacts-io.vala`, `contacts-io-parser.vala`, `contacts-io-vcard-parser.vala`, `contacts-io-export-operation.vala`, `contacts-io-vcard-export-operation.vala`, `contacts-io-parse-operation.vala`, `contacts-io-parse-main.vala` | `lib/vcard.rb` | vCard 4.0 (RFC 6350) parse/serialise | done |
| `src/contacts-operation.vala`, `contacts-operation-list.vala`, `contacts-delete-operation.vala`, `contacts-link-operation.vala`, `contacts-unlink-operation.vala`, `contacts-import-operation.vala` | `lib/operations.rb` | undoable operations + undo stack | done — upstream's operations are async (EDS over D-Bus); file-backend equivalents run synchronously |
| `src/contacts-chunk-filter.vala`, `contacts-chunk-empty-filter.vala`, `contacts-chunk-property-filter.vala`, `contacts-chunk-sorter.vala`, `contacts-manual-filter.vala`, `contacts-persona-filter.vala`, `contacts-persona-sorter.vala`, `contacts-individual-sorter.vala`, `contacts-individual-section-sorter.vala`, `contacts-query-filter.vala`, `contacts-contact-selection-model.vala` | `lib/contact_store.rb` | list filter/sort/selection chain | done — collapsed into one `ListStore -> FilterListModel -> SingleSelection` chain with Ruby-side sort (works around a `Gtk::CustomSorter`/`Gio::ListStore#sort` binding bug, per in-file comment) |
| `src/contacts-settings.vala` + `src/org.gnome.Contacts.gschema.xml` | `lib/settings.rb` | app settings | done — backed by a JSON file under `XDG_CONFIG_HOME` instead of GSettings (no system schema install step) |
| `src/contacts-esd-setup.vala` | `lib/accounts_list.rb` / `lib/setup_window.rb` (implicit) | EDS address-book provisioning on first run | **missing as its own file** — folded informally into the setup flow; EDS itself is out of scope (no EDS backend), but confirm the first-run gating logic (`did-initial-setup`) still matches |
| `src/contacts-utils.vala` | — | misc helper functions | **surveyed, nothing to port** — every function but two is Folks/EDS persona-store plumbing (`persona_is_main`, `has_main_persona`, `is_ignorable`, `can_remove_personas`, `personas_as_list_model`, `format_persona_store_name*`, `persona_is_google*`) with no counterpart in a port that has no Folks and one `Contact` per entry rather than personas linked under an `Individual`; `get_stock_avatars` (scan `pixmaps/faces` for face images) is superseded by `AvatarSelector::STOCK_ICONS` (symbolic icon names from the icon theme, a different and simpler stock-avatar source); `get_first` and `string_is_non_empty_closure` are one-line GLib-closure conveniences with direct Ruby equivalents (`collection.first`, `!str.to_s.empty?`) wherever a caller needs them, not helpers worth a shared file |
| `src/contacts-shell-search-provider.vala` + `data/org.gnome.Contacts.search-provider.ini.in` + `data/org.gnome.Contacts.SearchProvider.service.in` | `lib/shell_search_provider.rb` | GNOME Shell search provider (D-Bus) | done |
| Persistence backends (no direct upstream equivalent — upstream only has EDS) | `lib/backend.rb`, `lib/json_backend.rb`, `lib/vcard_backend.rb` | storage backends | done — port-specific, replaces Evolution Data Server |

## Data / resources (not Ruby components, but parity-relevant)

| Upstream | Kind | Status |
|---|---|---|
| `data/org.gnome.Contacts.gschema.xml` | GSettings schema | superseded by `lib/settings.rb`'s JSON store (see above) |
| `data/contacts.gresource.xml` | GResource manifest | not applicable — Ruby port has no `.ui`/GResource bundle by house style |
| `data/ui/*.blp` (9 files) | blueprint UI | each has a `lib/*.rb` counterpart listed above; all 9 are accounted for |
| `data/icons/**/*.svg` (action icons: birthday, building, calendar, chat, external-link, image-round, map, note, photo-camera, qr-code, website; app icons) | icon assets | **not verified** — need to confirm each icon name used in upstream `.blp`/`.vala` (via `icon-name=`) has a matching available icon at runtime; not checked in this survey |
| `data/style.css` | stylesheet | **not verified** — no corresponding check that port widgets apply the same CSS classes upstream's stylesheet targets |
| `data/org.gnome.Contacts.metainfo.xml.in.in`, `.desktop.in.in`, `.service.in` | app metadata/registration | out of scope for a gem port; not applicable |
| `po/*.po` (89 locale files) + `po/POTFILES.in` | translation catalogue | **not started** — no `po/` directory, no gettext wiring in `lib/`; this is the subject of a separate `translation-parity` pass, flagged here for visibility |
| `tests/` (core chunk tests, vcard tests) | upstream test suite | for `test-parity` pass, not this inventory |

## Gaps and open questions surfaced by this survey

1. **Dead scaffold code** — resolved: `lib/gnome_contacts/application.rb`,
   `lib/gnome_contacts.rb`, and `exe/gnome-contacts` are deleted. They were
   never reachable from the real entry point (`exe/gnome-contacts-rb`, which
   boots `App` from `lib/main.rb`), and `gnome-contacts-rb.gemspec` only ever
   declared `exe/gnome-contacts-rb` as the executable.
2. **`src/contacts-utils.vala`** — resolved, see the Data model / IO table
   above: traced helper-by-helper; nothing was silently dropped, the port
   simply has no Folks/persona layer for most of it to apply to.
3. **`src/contacts-esd-setup.vala`** (EDS-specific first-run address-book setup)
   has no dedicated port file; the first-run gating (`did-initial-setup`) and
   address-book listing appear to be covered by `lib/setup_window.rb` and
   `lib/accounts_list.rb`, but this was not verified line-by-line against the
   Vala source.
4. **Icon assets and `data/style.css`** were not checked for parity — upstream
   ships 11 custom scalable action icons plus app icons and a stylesheet that
   targets specific CSS classes; no check was done that the port's widgets use
   matching icon names/CSS classes.
5. **Header-bar / primary menu model** in `contacts-main-window.blp` was not
   scanned at the widget/menu-item level against `lib/main.rb`; only the
   window-action list was confirmed.
6. **`po/` / translation catalogue**: entirely unaddressed; upstream ships 89
   locale `.po` files plus `POTFILES.in`/`POTFILES.skip`, and the port has no
   gettext integration at all.

## Summary

- Upstream Vala/C source files: 50 (`src/**/*.vala`, `src/**/*.c`, `src/**/*.h`)
- Upstream blueprint UI files: 9 (`data/ui/*.blp`)
- `lib/*.rb` files mapped to a specific upstream file: 29 of 33 non-scaffold,
  non-infrastructure files (`accounts_list.rb`, `avatar.rb`, `avatar_selector.rb`,
  `birthday_editor.rb`, `contact_editor.rb`, `contact_list.rb`, `contact_pane.rb`,
  `contact.rb`, `contact_sheet.rb`, `contact_sheet_row.rb`, `contact_store.rb`,
  `crop_dialog.rb`, `editable_avatar.rb`, `im_service.rb`, `import_dialog.rb`,
  `link_suggestion_grid.rb`, `main.rb`, `operations.rb`, `preferences_dialog.rb`,
  `qr_code_dialog.rb`, `settings.rb`, `setup_window.rb`, `shell_search_provider.rb`,
  `shortcuts_dialog.rb`, `type_combo_row.rb`, `type_set.rb`, `vcard.rb`)
- Port-only files with no upstream counterpart (new persistence layer,
  replacing EDS): `backend.rb`, `json_backend.rb`, `vcard_backend.rb`
- Stub/dead files `gnome_contacts.rb` and `gnome_contacts/application.rb`,
  plus the unreachable `exe/gnome-contacts`, have been deleted.
- Runtime dependencies are now declared in the gemspec and wired through
  `nix/Gemfile` / `nix/gemset.nix` / `flake.nix`: the toolkit itself
  (`glib2`, `gtk4`, `adwaita`), `base64` and `rqrcode_core` (already used by
  `contact.rb` and `qr_code_dialog.rb` but missing from the runtime closure,
  which broke `exe/gnome-contacts-rb` under a bundled install), and the five
  binding gems this round adds (`ashpd`, `edataserver`, `glycin`,
  `libglycin-gtk4`, `goa-rb`) — proved to load and populate their namespace
  (`Ashpd`, `EDataServer`, `Gly`, `GlyGtk4`, `Goa`) under `nix develop`.
  None of the five are wired into component behaviour yet beyond the one
  comment update in `avatar_selector.rb` noting what `Ashpd::Camera` does and
  does not provide (a presence check, not a capture) — see "remaining" in
  this round's report for what full integration of each would still need.
- No user-facing upstream window/dialog/page is currently fully **missing**
  from `lib/`; the gaps found are at the sub-component level (icons, CSS,
  menu model, EDS-setup detail, translations) and are listed above for
  follow-up passes.
