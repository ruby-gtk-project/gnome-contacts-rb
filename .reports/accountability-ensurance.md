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

## This round — the five hits above were rewritten, not just discussed

A prior round of this report *described* the five hits in
`component-inventory.md` and quoted what the rewrite should say, but never
edited the file itself — the excuse language was still live in a committed
report, un-rewritten, for however many rounds separated that write from this
read. That is the exact failure this skill exists to catch: a document about
the excuse is not the same as removing it, and a reader of
`component-inventory.md` alone (not this file) would still have met "by
design" and "out of scope" as filed decisions.

Fixed this round, in place, in `component-inventory.md` itself:

- Preferences dialog EDS toggle row — rewritten to the first-person admission
  form, cited above.
- `contacts-esd-setup.vala` row — "EDS itself is out of scope" rewritten to
  name the unverified gating logic as a gap, first person.
- GResource manifest row — this one genuinely is a non-gap under
  `component-parity`'s own rules (house style, no `.ui`/GResource by design
  across every port in this fleet), so it was not rewritten as an admission;
  it was reworded away from "not applicable" to a located correspondence
  statement, since even a legitimate non-gap should not be phrased as a
  dismissal.
- Metadata/`.desktop`/metainfo row — rewritten to the first-person admission
  form, cited above.

Re-ran `find-excuses.sh .` after the edits: zero hits remain in
`component-inventory.md`. One more surfaced and was fixed in the same pass —
`component-parity.md:75` referenced the old "by design" phrasing in a
parenthetical rather than restating the gap; reworded to point at the fix
instead of the stale language. `component-parity.md:67` ("acceptable" for
the QR renderer substitution) was re-checked against the rule below and left
as-is; see that section.

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

The task's stated gate this round — `drive_ok=true, 59 checks passed, 0
failed, covering 13 components` — is real; re-run this round
(`nix develop --command xvfb-run -a ruby test/drive_main_window.rb`) and
reproduced exactly: `59 of 59 checks passed` / `DRIVE OK`. The unit suite was
also re-run (`nix develop --command xvfb-run -a ruby` running every
`test/test_*.rb`): `137 runs, 452 assertions, 0 failures, 0 errors, 0 skips`,
also green. Neither of those is a false claim on its own terms.

It is, however, at risk of being read as broader than it is, and this report
exists partly to block that reading:

- **"13 components" is `test/drive_main_window.rb`'s own count of the
  `lib/*.rb` files it names directly, out of 31 non-scaffold files** — not a
  claim that 13/13 upstream *windows* have parity, and `drive-test.md` says
  so explicitly. A reader who sees "59/59, 13 components" and infers "the UI
  layer has parity" has been misled by omission, not by any false statement
  in the gate itself. `drive-test.md` also names, by file, what neither suite
  exercises at all: `lib/setup_window.rb`/`lib/accounts_list.rb` (first-run
  picker, unreachable with the drive's single-backend `App.new`),
  `lib/avatar.rb`/`lib/avatar_selector.rb`/`lib/editable_avatar.rb`/
  `lib/crop_dialog.rb` (avatar pick/crop), `lib/link_suggestion_grid.rb`/
  `lib/dont_suggest_store.rb` (duplicate-link suggestions), and the IM/type
  combo rows beyond fixture population. Those are unverified, not done — the
  runtime gate passing says nothing about them one way or the other.
- **It says nothing about translation.** None of the components it drives
  exercises a single translated string, because the port has none (see
  `translation-parity.md` — still no `po/` directory this round). A reader
  who sees the gate pass and infers "the UI layer has parity" is wrong about
  every string the app shows.
- **It did not catch the leap-day birthday bug** (`component-parity.md` #2),
  because the drive script's fixture contacts don't include a Feb 29
  birthday and the drive doesn't advance the clock. A green integration
  drive and a wrong unit of logic coexist; the gate is real, and it is not
  sufficient, and no prior document said so.
- **137/137 unit tests green** is in the same position: real, and not
  evidence of parity with upstream's 38 Vala `Test.add_func` cases, because no
  one has built the bijective census `test-parity.md` itself says is
  "not established" — roughly 18 of the 38 upstream chunk property/is-empty
  tests remain un-censused this round, not just un-ported. Citing "all green"
  as if it answered "is it ported" would be the false-green pattern this
  skill exists to catch; `test-parity.md` takes care to say "green AND
  uncensused" rather than let the green stand in for the census.

## Verdict

Not clean. This round found and fixed four excuse-pattern hits that had
survived un-rewritten in `component-inventory.md` across however many prior
rounds flagged but never fixed them, plus one stale reference in
`component-parity.md`. Code itself (`lib/`, `exe/`) is clean of excuse
language, and no `PORTING.md` or `FINDINGS.md` exists to carry the pattern at
the top level. The runtime gate and unit suite are both genuinely green on
re-run, and both are narrower than a casual reading suggests: silent on
translation entirely, blind to at least one confirmed logic bug, and resting
on a test census that is explicitly incomplete rather than complete-and-green.
That gap between "green" and "proven" is the finding this report exists to
keep from being inherited as settled.
