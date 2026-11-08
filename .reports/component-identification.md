# Component identification — gnome-contacts-rb vs. origin/main

Method: `component-identification` skill. `gir-symbols.sh` output already
cached at `.claude/skills/component-identification/scripts/symbols.tsv`;
`component-scan.sh` run against a fresh `git archive origin/main` extraction
and against this tree's working copy this round.

## Upstream has declarative UI — read first

Upstream ships 13 blueprint files under `data/ui/*.blp`, each with exactly one
template (or, for the shortcuts window, one named top-level object):

| `.blp` template | Backing `.vala` | Port file |
|---|---|---|
| `$ContactsMainWindow : Adw.ApplicationWindow` | `contacts-main-window.vala` | `lib/main.rb` |
| `$ContactsContactPane : Adw.Bin` | `contacts-contact-pane.vala` | `lib/contact_pane.rb` |
| `$ContactsContactSheetRow : Adw.PreferencesRow` | `contacts-contact-sheet-row.vala` | `lib/contact_sheet_row.rb` |
| `$ContactsBirthdayEditor : Adw.Dialog` | `contacts-contact-editor.vala` (BirthdayEditor) | `lib/birthday_editor.rb` |
| `$ContactsEditableAvatar : Widget` | `contacts-editable-avatar.vala` | `lib/editable_avatar.rb` |
| `$ContactsAvatarSelector : Adw.Dialog` | `contacts-avatar-selector.vala` | `lib/avatar_selector.rb` |
| `$ContactsCropDialog : Adw.Dialog` | `contacts-crop-dialog.vala` + `cc-crop-area.c` | `lib/crop_dialog.rb` |
| `$ContactsImportDialog : Adw.Dialog` | `contacts-import-dialog.vala` | `lib/import_dialog.rb` |
| `$ContactsLinkSuggestionGrid : Box` | `contacts-link-suggestion-grid.vala` | `lib/link_suggestion_grid.rb` |
| `$ContactsQrCodeDialog : Adw.Dialog` | `contacts-qr-code-dialog.vala` | `lib/qr_code_dialog.rb` |
| `$ContactsPreferencesWindow : Adw.PreferencesDialog` | `contacts-preferences-window.vala` | `lib/preferences_dialog.rb` |
| `$ContactsSetupWindow : Adw.ApplicationWindow` | `contacts-setup-window.vala` | `lib/setup_window.rb` |
| `Adw.ShortcutsDialog shortcuts_dialog` (named root, no template) | n/a (built inline) | `lib/shortcuts_dialog.rb` |

All 13 declarative units have exactly one corresponding port file — no
1:1-mapping gap at this level. Good.

Upstream also builds components with **no** declarative file (code-only):
`contacts-contact-sheet.vala`, `contacts-type-combo.vala`, and the
`contacts-accounts-list.vala` rows. These map to `lib/contact_sheet.rb`,
`lib/type_combo_row.rb`, `lib/accounts_list.rb` respectively — present.

## Widget-count spot checks (adversarial, not exhaustive)

**Main window.** Upstream `contacts-main-window.blp` names 9 `Button`s
(`add_button`, `selection_button`, `select_cancel_button`, `export_button`,
`link_button`, `delete_button`, `cancel_button`, `edit_contact_button`,
`done_button`). `lib/main.rb` constructs 10 `Gtk::Button.new` call sites. The
extra one was read, not assumed: it is a header-bar overflow/menu trigger
built alongside the `Gtk::MenuButton`s rather than a bare button upstream
also has — not a fabricated widget, but worth noting the scan's raw count
does not land on the same number as the `.blp` and a reader has to open both
sides to confirm it's benign.

**Avatar selector camera button.** Present on both sides
(`camera_button` in the `.blp`, `lib/avatar_selector.rb#camera_button`), same
icon name (`camera-photo-symbolic`), same `clicked` signal — but see
`component-parity.md`: the signal handler's *behaviour* diverges sharply
(upstream opens a live capture stream; the port shows a "not supported"
dialog). Identity at the widget/signal level is not identity of behaviour.

## Repeaters and dynamic state (read, not scanned)

- `lib/contact_list.rb` rows are a repeater over the store's filtered
  `SingleSelection`, matching upstream's `ContactListRow` factory pattern —
  same shape, confirmed by reading both.
- `lib/link_suggestion_grid.rb` builds one row per suggested match
  (repeater), matching `contacts-link-suggestion-grid.vala`.
- `lib/contact_sheet_row.rb` is instantiated once per populated chunk
  (email, phone, etc.) by `contact_sheet.rb`, mirroring upstream's per-chunk
  row construction in `contacts-contact-sheet.vala`.

## Non-widget inventory not covered by the scan

- **Actions.** `lib/main.rb` installs actions via `Gio::SimpleAction.new`
  with literal string names (`'add-contact'`, `'edit-contact'`,
  `'delete-contact'`, `'link-contact'`, `'export-contact'`, `'undo'`, etc. —
  read directly off the `add_action` call sites, not inferred). These match
  upstream's `win.*` action names 1:1 by name where checked; see
  `component-parity.md` for behavioural confirmation (undo/redo in
  particular).
- **Keyboard shortcuts.** `lib/shortcuts_dialog.rb` lists shortcut rows;
  cross-checked against `data/ui/contacts-shortcuts-dialog.blp` — see
  `component-parity.md` for the row-by-row comparison.

## Scope note

This is a re-identification pass, not a from-scratch inventory — a prior
`.reports/component-inventory.md` already maps every upstream source file to
a port file at the file level. This pass's job was to verify that mapping
against the declarative `.blp` layer specifically (which the prior inventory
does not do file-by-file for widget *counts*) and to spot-check counts. No
upstream `.blp` template was found without a corresponding port file, and no
port file was found building a component with no upstream source. The
camera-capture divergence and the main-window button-count footnote above
are the only identification-level findings from this pass; the parity
report below carries the behavioral verdicts.
