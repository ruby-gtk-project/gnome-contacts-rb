# Translation parity — gnome-contacts-rb vs. origin/main

Re-verified fresh this round (not carried over unread from a prior report).

## Upstream

- `git ls-tree -r --name-only origin/main | grep '^po/'` → 82 files:
  `LINGUAS`, `POTFILES.in`, `POTFILES.skip`, and 79 `.po` files (one per
  language/locale, including variants like `ca@valencia.po`, `en_CA.po`,
  `en_GB.po`).
- `po/POTFILES.in` (re-read this round, 62 lines) lists every `.blp` and
  `.vala` file that carries translatable strings — 14 `.blp` files plus 38+
  `.vala` files, covering every window, dialog and the desktop/metainfo
  files.
- Strings are marked via Vala's `_()`/`C_()` and the blueprint compiler's
  translatable string markers, extracted into a `.pot` and distributed as
  the `.po` files above.

## Port

- `grep -rln "gettext\|_(\"|FastGettext" lib/ exe/` → zero matches, re-run
  this round.
- `find . -iname '*.po' -o -iname LINGUAS` (excluding `.git`) → zero
  matches. No `po/` directory exists.
- `Gemfile` / gemspec → no `gettext`, `fast_gettext`, or any i18n gem
  listed.
- Every user-visible string in `lib/` — row labels, dialog titles, button
  text, the shortcuts-dialog entries, the birthday banner — is a bare Ruby
  string literal with no translation marker of any kind.

## Verdict

**Total gap, unchanged from the prior round.** 0 of the ~hundreds of
upstream msgids survive in any form — not a subset, not a stub catalogue,
nothing. 0 of 79 shipped languages are reachable. This is not softened by
anything found elsewhere in this round's audit: it remains the single
largest parity failure in the port, exceeding every other finding across
all five reports combined in raw scope (79 languages × hundreds of strings
vs. a handful of behavioral/test gaps). `.reports/component-inventory.md`
discloses this honestly as "not started," which is the right way to report
it — but an honest disclosure of a gap this size does not make the gap
smaller.
