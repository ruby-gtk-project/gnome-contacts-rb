# Accountability ensurance — gnome-contacts-rb

Grepped fresh this round: `lib/`, `exe/`, `test/`, `.reports/`, and for
`PORTING.md` (does not exist in this repo — nothing to grep there).

```
grep -rniE "TODO|FIXME|XXX|not implemented|for now|in a future|stub|unimplemented|hack\b" lib/ exe/ test/
```

Hits, read individually:

- `test/drive_main_window.rb:470` — `# a stub.` inside a comment explaining
  that the live portal call is *not* a stub (proving it raises for real in
  a sandbox with no portal daemon). Not an excuse; the opposite of one.
- Three `Date.stub(...)` lines in `test/test_contact.rb` — Minitest's
  `Object#stub` test helper, unrelated to the banned phrase's meaning.

No `TODO`, `FIXME`, "not implemented," "for now," or "in a future" survives
in `lib/` or `exe/` — the application code itself makes no excuses in
comments.

## Where a gap is disclosed vs. where it is minimized

- `.reports/component-inventory.md:30` flags camera capture as "stubbed" in
  its own summary table, with a pointer to a fuller note. Read that fuller
  note (`lib/avatar_selector.rb:11-19`): it correctly states the camera
  capture path is unported and explains the underlying portal-binding
  limitation in `ashpd`. **This is honest accounting, not an excused gap** —
  it says what's missing and why, in both the code and the report, rather
  than asserting parity. Carried into `component-parity.md` this round as a
  live finding, not just a citation.
- `.reports/drive-test.md` lists, under "Still not exercised by either
  suite," the setup window/accounts-list first-run flow and the IM-
  service/type-combo-row paths — again, disclosed rather than buried. This
  round's `component-parity.md` and `test-parity.md` both treat these as
  real, counted gaps rather than accepting the disclosure as a substitute
  for fixing them — disclosure is good practice, but it does not change
  the "unverified" status the task's runtime-gate framing assigns to an
  un-exercised component.

## Where a claim is at risk of reading as false-green

- **The devshell's own banner-advertised spec command does not work.**
  `ruby -e 'require "rspec/core"; ...'` against `spec/` produces `0
  examples, 0 failures, 2 errors occurred outside of examples` because
  `spec_helper.rb` requires the uninstalled `kettle-test` gem. Read in
  isolation (without the error text above it), "0 failures" is exactly the
  shape of a false green: a reader who trusts the banner's command and
  skims past the `LoadError` sees a suite that looks clean because it never
  ran. This is called out explicitly in `test-parity.md` this round. It
  is not, as far as this pass can tell, being *claimed* as passing by
  anyone in the repo's own reports — `drive-test.md` already correctly
  identifies `spec/` as dead and points at `rake test` as the real suite —
  but the live footgun remains in the devshell banner itself and nothing
  in the repo has removed or fixed that advertised command. Flagging it
  here again because "already noted once, elsewhere" is not the same as
  "fixed," and a stale broken pointer that keeps getting footnoted instead
  of removed is itself a minor accountability smell.
- **The runtime gate's "15 components" and "76 checks" are accurate and
  reproduced this round** (re-ran the drive script fresh: `76 of 76 checks
  passed`, `DRIVE OK`) — not a stale number being repeated from memory.
  Good.
- **The "137 runs, 452 assertions, 0 failures" Minitest number is likewise
  reproduced fresh this round**, not quoted from a prior report without
  re-execution.

## Verdict

Not clean, but not because anyone is excusing a gap in prose — the opposite
problem: real gaps (camera capture, first-run setup flow, nine chunk-level
test files, all of translation) are disclosed candidly in the code and in
prior reports, but disclosure has accumulated across rounds without the
underlying gaps closing, and one small but real false-green risk (the dead
devshell spec command) has now been flagged twice without being fixed.
Accountability in the sense of "say what's missing" — good. Accountability
in the sense of "a flagged gap gets closed, or a flagged false-green risk
gets removed" — not yet, on any of the items above.
