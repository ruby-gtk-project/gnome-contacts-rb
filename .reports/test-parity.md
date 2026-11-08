# Test parity — gnome-contacts-rb vs. origin/main

## The suite actually runs — verified this round, not assumed

```
nix develop --command xvfb-run -a rake test
...
137 runs, 452 assertions, 0 failures, 0 errors, 0 skips
```

Executed fresh this round, not carried over from a prior report. This is
real: a GC-reentrancy abort in the `glib2`/`gobject-introspection` binding
layer that used to crash the drive script mid-run is documented
(`.reports/drive-test.md`) and worked around with `GC.disable` scoped to the
drive — the Minitest run above was not affected by that bug and needed no
such workaround.

Separately, the drive script (`test/drive_main_window.rb`, Minitest-adjacent
but not part of `rake test`) was also run fresh this round:
`76 of 76 checks passed`, `DRIVE OK`. Matches the stated runtime gate
exactly (drive_ok=true, 76/76, this round; 15 components is the count
`drive-test.md` enumerates by name — rechecked, matches).

## The dev-shell's own documented spec command is dead

The devshell banner (`nix develop`) prints, as one of three canonical
commands:

```
run the specs: ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'
```

Running it verbatim this round:

```
LoadError: cannot load such file -- kettle/test/rspec
...
No examples found.
Finished in 0.00008 seconds
0 examples, 0 failures, 2 errors occurred outside of examples
```

`spec/` contains only `spec_helper.rb` (which requires the uninstalled
`kettle-test` gem) and a README describing a harness that is never used —
there are no `spec/**/*_spec.rb` files anywhere in the tree. The project's
real test suite lives entirely under `test/*.rb` and runs via `rake test`,
not via the command the devshell advertises for "run the specs." This is
flagged in `.reports/drive-test.md` already (accurately), but it bears
repeating here because it is squarely a test-parity concern: **a command an
auditor is explicitly told to run, to check test parity, produces a
false-looking "0 failures" rather than an honest "this doesn't work."** `0
examples, 0 failures, 2 errors` is easy to misread at a glance as "no specs,
nothing to report" instead of "the configured harness cannot load." Treat
the devshell banner's rspec command as broken, not as an empty-but-passing
suite, and use `rake test` for all test-parity verification.

## Chunk-level upstream tests have no architectural counterpart — and no behavioral substitute either

Upstream ships ten dedicated GLib `Test.add_func` files under `tests/core/`
(`test-addresses-chunk.vala`, `test-birthday-chunk.vala`,
`test-email-addresses-chunk.vala`, `test-full-name-chunk.vala`,
`test-nickname-chunk.vala`, `test-notes-chunk.vala`, `test-phones-chunk.vala`,
`test-roles-chunk.vala`, `test-structured-name-chunk.vala`,
`test-urls-chunk.vala`), each asserting three things per chunk type:
`property-name-chunk` (the chunk registers under the right Folks property
name), `get-is-empty` (an item with all-blank fields reports
`is_empty == true`; populating a field flips it to `false`), and
`serialize-basic` (`to_gvariant`/`apply_gvariant` round-trip survives).

None of these three assertions have a literal counterpart in
`test/test_contact.rb`, because the GVariant/Folks-chunk machinery itself
was deliberately not ported — `lib/contact.rb`'s own header comment explains
why (plain two-field `Data` structs replace `Chunk` subclasses since there
is no Folks object needing mid-edit validity). That architectural call is
reasonable and disclosed, not hidden. **But the behavioral content of those
tests — does an email/phone/role/url/note/nickname/address with every field
blank count as empty, and does populating it un-empty it, and does the data
round-trip through serialization — is not independently tested anywhere in
the Ruby suite either.** `test/test_vcard.rb`'s
`test_round_trip_preserves_every_field` exercises serialization for a
*fully populated* contact only; it never constructs an empty-but-present
field and asserts an `is_empty`-equivalent predicate, because no such
predicate is called out by name in any Ruby test. `test/test_contact.rb`
itself only tests `display_name` fallback and `Contact::Birthday`
(`test_birthday_parses_iso_strings_and_survives_garbage`,
`test_birthday_today`, `test_birthday_today_leap_day`) — 3 of its 14 tests
map to upstream chunk tests (birthday); the other 9 upstream chunk test
files (addresses, email, full_name, nickname, notes, phones, roles,
structured_name, urls) have **no corresponding assertion**, direct or
indirect, in the Ruby suite. This is a real test-parity gap, independent of
whether the underlying feature works — it was not possible to find, by
reading the test files, a Ruby test that would fail if `EmailAddress`'s (or
any of the other eight types') blank-vs-populated handling broke.

## vCard-specific upstream tests — ported

`tests/io/vcard/test-vcard-bday.vala`, `test-vcard-email.vala`,
`test-vcard-minimal.vala` → `test/test_vcard.rb`'s
`test_round_trip_preserves_every_field`,
`test_parse_handles_foreign_cards`, `test_parse_ignores_empty_cards`, and
others cover the same ground (minimal cards, birthday field, email field)
plus more (folding, special characters, typed-value objects) that upstream
does not test. Good coverage here, re-read this round line by line.

## `tests/basic-test.vala` — the GLib test-suite entry point

This file just registers the other `Test.add_func` suites with GLib's test
runner; it has no behavior of its own to port. Not a gap.

## Verdict

Not clean. `rake test` is real and passing (137/452, re-run fresh this
round) and the drive script matches the stated gate (76/76). But: (1) the
devshell's own posted spec command is dead and silently prints a
passing-looking result, which is exactly the shape of a false-green an
auditor could walk away with if they ran only what the banner told them to;
(2) nine of upstream's ten chunk-level test files have no ported behavioral
equivalent, only an architectural explanation for why the literal GVariant
assertions don't apply — the *empty/populated* semantics they test were
never independently re-verified for anything except birthday.
