# Component inventory — gnome-contacts-rb vs upstream (origin/main)

Surveyed 2026-11-07. Scope: every upstream file that contributes a
user-facing component (windows, dialogs, pages, rows, menus, shortcuts,
preferences, actions, empty/error states) plus its `.blp`, GSettings schema,
GResource manifest and `po/` catalogue. No app code was written in this
pass.

Legend: **present** = a `lib/*.rb` file exists that ports this upstream
file's behaviour (possibly collapsed with siblings, as the house style's
GTK4 idiom often prefers over porting a helper class 1:1 — noted where that
happens). **missing** = nothing in `lib/` corresponds to it.

## Windows, pages and dialogs

| Upstream file(s) | → `lib/*.rb` | Kind | Present? |
|---|---|---|---|
| `src/main.vala`, `src/contacts-app.vala`, `src/contacts-main-window.vala`, `data/ui/contacts-main-window.blp` | `lib/main.rb` | app + main window (header bar, search bar/button, `Adw::NavigationSplitView`, menu, actions, accelerators, About dialog) | yes |
| `src/contacts-setup-window.vala`, `data/ui/contacts-setup-window.blp` | `lib/setup_window.rb` | first-run wizard window | yes |
| `src/contacts-preferences-window.vala` | `lib/preferences_dialog.rb` | preferences dialog | yes |
| `data/ui/contacts-preferences-window.blp` | `lib/preferences_dialog.rb` | preferences dialog UI | yes |
| `data/ui/contacts-shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | keyboard shortcuts window | yes |
| `src/contacts-contact-list.vala` | `lib/contact_list.rb` | contact list pane (left side of split view) | yes |
| `src/contacts-contact-pane.vala`, `data/ui/contacts-contact-pane.blp` | `lib/contact_pane.rb` | detail pane, empty state, edit/view toggle | yes |
| `src/contacts-contact-sheet.vala` | `lib/contact_sheet.rb` | read-only contact detail sheet | yes |
| `src/contacts-contact-sheet-row.vala`, `data/ui/contacts-contact-sheet-row.blp` | `lib/contact_sheet_row.rb` | one field row in the sheet | yes |
| `src/contacts-contact-editor.vala` | `lib/contact_editor.rb` | edit form | yes |
| `src/contacts-contact-editor.vala` (BirthdayEditor class), `data/ui/contacts-birthday-editor.blp` | `lib/birthday_editor.rb` | day/month/year birthday picker | yes |
| `src/contacts-avatar.vala` | `lib/avatar.rb` | avatar display widget | yes |
| `src/contacts-avatar-selector.vala`, `data/ui/contacts-avatar-selector.blp` | `lib/avatar_selector.rb` | stock-avatar grid + file/camera chooser dialog | yes (camera capture itself is stubbed — see note below) |
| `src/contacts-editable-avatar.vala`, `data/ui/contacts-editable-avatar.blp` | `lib/editable_avatar.rb` | avatar + pencil-button overlay | yes |
| `src/contacts-crop-dialog.vala`, `data/ui/contacts-crop-dialog.blp`, `src/cc-crop-area.c/.h` | `lib/crop_dialog.rb` | square crop dialog | yes |
| `src/contacts-import-dialog.vala`, `data/ui/contacts-import-dialog.blp`, `src/contacts-import-operation.vala` | `lib/import_dialog.rb` | vCard import picker/dialog | yes |
| `src/contacts-link-suggestion-grid.vala`, `data/ui/contacts-link-suggestion-grid.blp` | `lib/link_suggestion_grid.rb` | "possible duplicate" suggestion grid under the sheet | yes |
| `src/contacts-qr-code-dialog.vala`, `data/ui/contacts-qr-code-dialog.blp` | `lib/qr_code_dialog.rb` | QR-code share dialog | yes |
| `src/contacts-accounts-list.vala` | `lib/accounts_list.rb` | address-book list (used by setup window + preferences) | yes |
| `src/contacts-type-combo.vala` | `lib/type_combo_row.rb` | type (Home/Work/…) combo row | yes |

## Core model, backends and operations

| Upstream file(s) | → `lib/*.rb` | Kind | Present? |
|---|---|---|---|
| `src/core/contacts-contact.vala`, `contacts-structured-name-chunk.vala`, `contacts-im-addresses-chunk.vala`, `contacts-avatar-chunk.vala`, `contacts-addresses-chunk.vala`, `contacts-alias-chunk.vala`, `contacts-birthday-chunk.vala`, `contacts-email-addresses-chunk.vala`, `contacts-full-name-chunk.vala`, `contacts-nickname-chunk.vala`, `contacts-notes-chunk.vala`, `contacts-phones-chunk.vala`, `contacts-roles-chunk.vala`, `contacts-urls-chunk.vala`, `contacts-bin-chunk.vala`, `contacts-chunk.vala` | `lib/contact.rb` | contact model + per-field "chunk" classes, collapsed into one file (each field group is a plain class — `StructuredName`, `Avatar`, `TypedValue`, etc. — rather than 15 separate GObject chunk subclasses) | yes |
| `src/core/contacts-type-set.vala`, `contacts-type-descriptor.vala`, `contacts-vcard-type-mapping.vala` | `lib/type_set.rb` | type (Home/Work/Other…) descriptor sets | yes |
| `src/contacts-store.vala` | `lib/contact_store.rb` | the master contact `ListStore`/filter/selection model, merge/link bookkeeping | yes |
| `src/contacts-chunk-filter.vala`, `contacts-chunk-empty-filter.vala`, `contacts-chunk-property-filter.vala`, `contacts-manual-filter.vala`, `contacts-persona-filter.vala`, `contacts-query-filter.vala` | `lib/contact_store.rb` (`Gtk::CustomFilter`) | search/filter predicates, collapsed into one `Gtk::CustomFilter` block instead of six Filter subclasses | yes (collapsed — GTK4 `Gtk::CustomFilter` is the idiomatic replacement for GTK3-era `Gtk::TreeModelFilter`-style Filter subclasses; worth a reviewer's sign-off that nothing upstream's six classes did is missing, but not a gap in behaviour) |
| `src/contacts-chunk-sorter.vala`, `contacts-individual-sorter.vala`, `contacts-individual-section-sorter.vala`, `contacts-persona-sorter.vala` | `lib/contact_store.rb` | sort order (alpha, surname-first) | partially — `contact_store.rb` sorts the `Gio::ListStore` directly; confirm section/letter-heading grouping (upstream's `IndividualSectionSorter` feeds an index/section header in the list) has an equivalent in `contact_list.rb` |
| `src/contacts-contact-selection-model.vala` | `lib/contact_store.rb` (`Gtk::SingleSelection`) | selection model | yes (collapsed to stock `Gtk::SingleSelection`) |
| `src/contacts-ui-state.vala` | — (no dedicated file; state is implicit in `main.rb`'s `NavigationSplitView`/pane visibility) | app-wide UI mode enum (NORMAL/CREATE/EDIT/…) | **missing as an explicit construct** — behaviour may be reproduced ad hoc in `main.rb`/`contact_pane.rb`, but there is no single place that encodes upstream's state machine, so edge-case transitions (e.g. what happens mid-edit when a sync adds/removes the selected contact) are not provably covered |
| `src/contacts-utils.vala` | — | `Utils.get_first`, `Utils.get_stock_avatars` (reads `$XDG_DATA_DIRS/pixmaps/faces`), `Utils.has_main_persona`, `Utils.format_persona_stores` | **missing as a module** — `avatar_selector.rb` hardcodes a symbolic-icon list instead of reading the system stock-avatar directory (documented deviation); `has_main_persona`/`format_persona_stores` describe multi-persona (Folks) provenance text this port's single-persona model has no use for |
| `src/contacts-operation.vala`, `contacts-operation-list.vala`, `contacts-delete-operation.vala`, `contacts-link-operation.vala`, `contacts-unlink-operation.vala` | `lib/operations.rb` | undo stack + delete/link/unlink operations | yes |
| `src/contacts-im-service.vala` | `lib/im_service.rb` | IM protocol metadata (icons, names) | yes |
| `src/contacts-settings.vala`, `src/org.gnome.Contacts.gschema.xml` | `lib/settings.rb` | persisted settings | yes, deliberately backed by JSON instead of GSettings (documented deviation — no compiled schema needed to run from a checkout) |
| `src/contacts-esd-setup.vala` | `lib/eds_backend.rb` | EDS source-registry discovery | yes (via `EDataServer` gem) |
| `src/io/contacts-io.vala`, `contacts-io-parser.vala`, `contacts-io-parse-operation.vala`, `contacts-io-parse-main.vala`, `contacts-io-export-operation.vala`, `contacts-io-vcard-parser.vala`, `contacts-io-vcard-export-operation.vala` | `lib/vcard.rb`, `lib/vcard_backend.rb` | vCard parse/export | yes |
| — (no 1:1 upstream file; Folks/EBookClient equivalent) | `lib/backend.rb`, `lib/json_backend.rb` | backend abstraction + JSON-file backend | yes — port-specific; not a gap |
| `src/contacts-shell-search-provider.vala`, `data/org.gnome.Contacts.search-provider.ini.in`, `data/org.gnome.Contacts.SearchProvider.service.in` | `lib/shell_search_provider.rb` | GNOME Shell search provider D-Bus interface | yes |
| — (no upstream equivalent class; app-invented) | `lib/dont_suggest_store.rb` | persists dismissed link-suggestions | yes — ports upstream's `add_no_suggest_link` methods off `contacts-store.vala`, already counted above |

## Packaging, data and translation assets — not components, but in scope per the task

| Upstream file | Present in port? |
|---|---|
| `data/org.gnome.Contacts.desktop.in.in` | missing — no `data/` directory in the port at all |
| `data/org.gnome.Contacts.metainfo.xml.in.in` | missing |
| `data/org.gnome.Contacts.service.in`, `.search-provider.ini.in`, `.SearchProvider.service.in` | missing as files (the search-provider *behaviour* is ported, see `shell_search_provider.rb` above — only the D-Bus activation/service files are absent) |
| `src/org.gnome.Contacts.gschema.xml` | intentionally not ported — superseded by `lib/settings.rb`'s JSON store (see above) |
| `data/contacts.gresource.xml` | not applicable — the Ruby port has no GResource bundle; icons/CSS are referenced directly |
| `data/style.css` | ported inline into `lib/main.rb` per that file's header comment |
| `data/icons/**` | not checked in this pass — app icon asset presence not verified |
| `po/*.po`, `po/POTFILES.in`, `po/LINGUAS` | missing — no `po/` directory in the port; translation parity is out of scope for this skill (see `translation-parity` skill) and not assessed further here |

## Notes / flags for the next pass

- The "missing" rows above (`contacts-ui-state.vala`, `contacts-utils.vala`'s
  stock-avatar/persona helpers, and all packaging/`po/` files) are the actual
  gaps found. Everything else that looked unmapped on a pure filename diff
  turned out to be deliberately collapsed into GTK4-idiomatic replacements
  (`Gtk::CustomFilter`, `Gtk::SingleSelection`, direct `Gio::ListStore` sort)
  and is counted present.
- `contacts-individual-section-sorter.vala` (alphabet section headers in the
  contact list) needs a closer read of `contact_list.rb` against the
  upstream `.blp`/list-view factory to confirm section headers render; this
  survey could not confirm it from the file list alone and the
  `component-parity` skill should verify it directly.
- `avatar_selector.rb`'s camera button is a real `Ashpd::Camera.present?`
  portal check (per its header comment) but capture itself is unavailable
  through the `ashpd` gem's current binding surface — documented in the file,
  not a silent gap.
