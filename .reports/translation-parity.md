# Translation parity — gnome-contacts-rb vs. origin/main

## Upstream

- `po/LINGUAS` lists the shipped languages; `git ls-tree -r --name-only
  origin/main | grep '^po/'` returns **82 files**: `LINGUAS`, `POTFILES.in`,
  `POTFILES.skip`, and **79 `.po` files** (one per language/locale, including
  variants like `ca@valencia.po`, `en_CA.po`, `en_GB.po`).
- Sampled `po/de.po`: **222 `msgid` entries.** (Spot check, not the full
  template count — `POTFILES.in` extraction was not re-run — but sufficient
  to size the catalogue: multiple hundreds of translatable strings across the
  UI.)
- Strings are marked in source via Vala's `_()` (gettext) in `.vala` files and
  the blueprint compiler's translatable markers in `.blp` files, both
  extracted into a `.pot` and distributed as the `.po` files above.

## Port

- `grep -rln "gettext\|_(\"" lib/ exe/` → **zero matches.**
- `find . -iname '*.po' -o -iname LINGUAS` (excluding `.git`) → **zero
  matches.** No `po/` directory exists at all.
- `Gemfile` / `gnome-contacts-rb.gemspec` → no `gettext`, `fast_gettext`, or
  any i18n gem listed as a dependency.
- No string anywhere in `lib/` is wrapped in a translation marker of any
  kind. Every user-visible string in the port — row labels, dialog titles,
  button text, the "Their birthday is today! 🎉" banner
  (`lib/contact_sheet.rb:175`), everything — is a bare Ruby string literal.

## What this means against the skill's three claims

1. **Key sets equal?** No. Upstream: ~hundreds of msgids (222 sampled from one
   locale file alone). Port: **0**. Not "fewer" — none.
2. **Byte-identical keys?** Vacuously fails — there is nothing to compare,
   since the port extracts no catalogue at all.
3. **Languages ship?** No. 79 upstream `.po` files, 0 carried over, 0 `.mo`
   built, 0 installed. Every one of the people who contributed a translation
   to gnome-contacts over fourteen years gets nothing from this port: a
   German, French, or Japanese user runs `gnome-contacts-rb` and sees English,
   permanently, regardless of their system locale.

## On "English-only for now"

`.reports/component-inventory.md`'s own closing table calls this "not
started" and flags it for "a separate `translation-parity` pass" — which is
this one. That is an honest flag, not an excuse, and is noted as such. But
per the skill: there is no softer state than `gap` for this, and "not started"
for the entirety of an app's i18n is not a partial result to report gently —
it is **the single largest parity failure in this port**, by a wide margin
over anything in the other four reports combined (79 languages and hundreds
of translated strings vs. a handful of behavioural bugs elsewhere).

## Verdict

**Total gap.** 0 of the upstream catalogue survives. Nothing is marked,
nothing is extracted, nothing ships. This is not a rough edge to note in
passing; it is the headline finding of this audit.
