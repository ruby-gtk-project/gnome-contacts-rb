# Test parity — gnome-contacts-rb vs. origin/main

Upstream ref recorded for this ledger: `origin/main` (read via `git show`/
`git ls-tree`, never checked out; `ruby` is an orphan branch so no merge-base
exists to derive this from later — record it here).

## Upstream census

Upstream's test suite is Meson + GLib `Test.add_func`, under `tests/`:

| File | `Test.add_func` count |
|---|---|
| `tests/basic-test.vala` | 1 |
| `tests/core/test-addresses-chunk.vala` | 3 |
| `tests/core/test-birthday-chunk.vala` | 5 |
| `tests/core/test-email-addresses-chunk.vala` | 3 |
| `tests/core/test-full-name-chunk.vala` | 3 |
| `tests/core/test-nickname-chunk.vala` | 3 |
| `tests/core/test-notes-chunk.vala` | 2 |
| `tests/core/test-phones-chunk.vala` | 3 |
| `tests/core/test-roles-chunk.vala` | 2 |
| `tests/core/test-structured-name-chunk.vala` | 3 |
| `tests/core/test-urls-chunk.vala` | 4 |
| `tests/io/vcard/test-vcard-bday.vala` | 3 |
| `tests/io/vcard/test-vcard-email.vala` | 2 |
| `tests/io/vcard/test-vcard-minimal.vala` | 1 |
| **Total** | **38** |

This is the assertion unit upstream itself chose (one `Test.add_func` call per
pinned property); it is the number test-parity is measured against.

## Port census

`test/test_*.rb` (Minitest, `def test_*`): 126 methods across 9 files
(`test_vcard.rb` 8, `test_backends.rb` 13, `test_contact.rb` 13,
`test_shell_search_provider.rb` 13, `test_operations.rb` 14,
`test_contact_store.rb` 11, `test_settings.rb` 6, `test_type_set.rb` 8,
`test_app.rb` 40). Running the suite (`nix develop --command xvfb-run -a ruby
-Ilib -Itest -e '...'`) this round: **134 runs, 442 assertions, 0 failures, 0
errors, 0 skips** — the gap between 126 defined methods and 134 runs was not
chased down in this pass (possible dynamically-defined test methods); flagging
rather than silently rounding.

The suite **does execute**, and green — that much is not a false claim. What
is missing is the thing test-parity actually requires: a named upstream-test
→ port-test census. No file in this repo performs that mapping. 126-vs-38 (or
134-vs-38) is not evidence of parity; a bijective census is, and it has never
been written down. That is itself a gap, independent of anything found below.

## Census, as far as this round traced it

| Upstream test | Port test | Verdict |
|---|---|---|
| `test-birthday-chunk.vala` / `test_leap_day_birthday` | `test_contact.rb:103` `test_birthday_today` | **gap** — port test covers only an exact-date match, not the Feb-29 case upstream pins; and the production code is wrong on that exact case (see `component-parity.md` #2). A correctly-named test would have caught it. |
| `test-birthday-chunk.vala` / `test_serialize_pre_epoch` | — | **gap** — no port test feeds a pre-1970 birthday through parse→serialize→reparse. (`Date` in Ruby handles pre-epoch dates fine at the language level, which is likely why nobody noticed; "probably fine" is not a test.) |
| `test-birthday-chunk.vala` / `test_serialize_basic` | `test_vcard.rb` round-trip tests (e.g. `test_round_trip_preserves_every_field`) | ported, informally — covers birthday round-trip as part of a bigger fixture rather than a dedicated case, acceptable per the skill (different formulation, same property pinned) |
| `test-urls-chunk.vala` / `test_get_absolute_url` | — | **gap** — behaviour exists (`lib/contact_sheet.rb:185`), no test calls it (see `component-parity.md` #3) |
| `test-addresses-chunk.vala` / `test_to_maps_uri` | — | **gap** — behaviour itself doesn't exist in the form upstream tests (see `component-parity.md` #1), so there is nothing to port a test for until the behaviour is built |
| `test-vcard-bday.vala` / `test_vcard_bday_differen_timezones` | `test_vcard.rb` (no explicit timezone case seen) | **gap** — not traced to a named equivalent this round |
| `tests/basic-test.vala` / `get_first` (`UtilsTests`) | — | **gap**, not a pass. `.reports/component-inventory.md` already excuses this one ("one-line GLib-closure convenience... not a helper worth a shared file") — that is exactly the "C-specific plumbing" exemption the `test-parity` skill rules out by name. The behaviour upstream pinned (first-or-null-safe accessor) still needs a Ruby test wherever it is now inlined, and does not have one. |
| chunk `property_name`/`is_empty` tests across all 9 core chunk files (≈18 of the 38) | — | **not traced** this round. Given the port collapsed Folks per-field `Chunk` classes into one `Contact`/`TypedValue` model (`component-inventory.md`'s own description), these 18 upstream tests have no obvious 1:1 target and were not individually matched to port tests. Recording as **not yet censused** rather than assuming they're covered. |

## Verdict

**Not established.** Confirmed gaps: 2 (leap-day, pre-epoch) are real missing
assertions on code whose non-leap-year behaviour is independently confirmed
wrong; 2 more (`to_maps_uri`, `get_absolute_url`) are missing because the
underlying behaviour gap/undertest means there's nothing to point a port test
at yet; 1 (timezone bday) and roughly 18 (chunk property/is-empty tests) are
simply un-censused — no one has gone test-by-test. The suite running green
(134/134) is real and worth recording, but it is evidence the port's own
tests pass, not evidence of parity with upstream's 38.
