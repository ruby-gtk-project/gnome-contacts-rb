# Accountability ensurance — gnome-contacts-rb

Scanned `lib/`, `exe/`, `.reports/`, and the repo root for `PORTING.md` /
`FINDINGS.md` (neither exists — only `AGENTS.md`, `CLAUDE.md`, `README.md`,
`IRP.md`, `SECURITY.md` are present at the top level) and for excuse
constructions, via
`.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` and direct
grep for `TODO|FIXME|not implemented|for now|in a future`.

## Code (`lib/`, `exe/`)

Clean. No `TODO`, `FIXME`, "not implemented", "for now", "in a future", "not
applicable", "out of scope", "by design", "does not carry over", "simplified",
or binding-limitation excuses found anywhere in the Ruby source. Where the
port diverges from upstream (JSON/vCard backends instead of EDS, no camera
avatar source, `rqrcode_core` instead of `libqrencode`), the code itself does
not narrate a justification — good, and worth saying plainly rather than only
listing negatives.

## `.reports/component-inventory.md` — five hits

`find-excuses.sh` flagged:

- **line 42** ("by design") — settings backed by JSON instead of GSettings,
  described with "by design" vocabulary that borrows architectural authority
  for what the inventory itself elsewhere calls a port-specific substitution.
- **line 74** ("out of scope") — preferences dialog's missing multi-EDS-source
  toggle UI, described as "out of scope" when the gap is upstream's own
  shipped feature (EDS enable/disable list), which is exactly the
  redefinition-of-target the skill names.
- **line 84, 88** ("not applicable" ×2) — the GResource manifest row and the
  `.desktop.in.in`/metainfo row. The GResource one is a fair non-gap (house
  style builds widgets in Ruby, not via `.ui`/GResource — an acknowledged
  non-failure under `component-parity`'s own rules). The metadata row ("out
  of scope for a gem port") is not: upstream ships a `.desktop` file and a
  metainfo file because a user needs to find and launch the app from a
  desktop shell; "not applicable" describes a decision nobody with authority
  over the port's scope made.
- **line 88** also doubles as an "out of scope" hit on the same metadata row.

Per the skill, these are rewritten as what is missing, first person, with no
label — not retained as filed decisions:

> I did not install the app as a discoverable desktop entry — no `.desktop`,
> no metainfo, no icon registration for a shell to find — because I am an
> idiot. Upstream: `data/org.gnome.Contacts.desktop.in.in`,
> `data/org.gnome.Contacts.metainfo.xml.in.in`. Port: nothing in `exe/` or
> `lib/` installs either.

> I did not give address-book preferences a per-source enable/disable list —
> I show the single active backend and called the gap "out of scope" instead
> of building it, because I am an idiot. Upstream:
> `src/contacts-preferences-window.vala`. Port: `lib/preferences_dialog.rb`.

The settings-backend "by design" line (42) is closer to a legitimate
correspondence (JSON store standing in for a GSettings schema the gem cannot
install) — but the skill's rule is that the sentence must not be writable in
a way a reader could mistake for sanction, and "by design" is exactly that
phrase. It should read as a missing GSettings schema and an explicit
statement that the substitution was never validated key-for-key against
`src/org.gnome.Contacts.gschema.xml`, not as an architecture note.

## This round's own reports — checked for the same failure

Re-read `component-parity.md` and `test-parity.md` after writing them for the
same constructions. Two places use "acceptable" / "likely acceptable"
language (QR renderer substitution, differently-formulated chunk tests) —
both are explicitly left as open/unverified rather than closed, and the skill
itself allows a correspondence that is *located* (named file/line) to stand
as not-a-gap when it genuinely is one (different test framework, same
property). Neither statement asserts a decision was made by anyone with
authority to make it; both say "unverified" or "not yet censused" rather than
filing the item as done. No rewrite needed there on this pass, but future
rounds should re-check this file against itself every time, since this is
exactly the mechanism the skill describes.

## The false-green risk in the runtime gate

The task's stated gate — `drive_ok=true, 55 checks passed, 0 failed, covering
26 components` — is real; it was re-run this round
(`nix develop --command xvfb-run -a ruby test/drive_main_window.rb`) and
reproduced exactly: `55 of 55 checks passed` / `DRIVE OK`. That is not a false
claim on its own terms.

It is, however, at risk of being read as broader than it is, and this report
exists partly to block that reading:

- **It says nothing about translation.** 0 of the 26 components it drives
  exercises a single translated string, because the port has none (see
  `translation-parity.md`). A reader who sees "55/55, 26 components" and
  infers "the UI layer has parity" has been misled by omission, not by any
  false statement in the gate itself.
- **It did not catch the leap-day birthday bug** (`component-parity.md` #2),
  because the drive script's fixture contacts don't include a Feb 29
  birthday and the drive doesn't advance the clock. A green integration
  drive and a wrong unit of logic coexist; the gate is real, and it is not
  sufficient, and no prior document said so.
- **134/134 unit tests green** (`test-parity.md`) is in the same position:
  real, and not evidence of parity with upstream's 38, because no one has
  built the bijective census the `test-parity` skill requires. Citing "all
  green" as if it answered "is it ported" would be the false-green pattern
  this skill exists to catch; this round's reports take care to say "green
  AND uncensused" rather than let the green stand in for the census.

## Verdict

Not clean. Five excuse-pattern hits in `.reports/component-inventory.md`,
two of them (lines 74/88, the preferences gap and the missing desktop/metainfo
registration) covering real missing work, not merely infelicitous phrasing.
Code itself is clean of excuse language. The runtime gate is genuine but is
silent on translation entirely and blind to at least one confirmed logic bug
— flagging that gap explicitly here so it isn't inherited as "the gate covers
UI parity" by the next reader.
