# Component parity — gnome-contacts-rb vs. origin/main

This builds on `component-identification.md` (which flags that the underlying
inventory is file-level, not widget-level) and on the existing
`.reports/component-inventory.md`. Below are the concrete discrepancies found
by reading upstream source against the port's `lib/` this round, plus the
pre-existing rows from `component-inventory.md` carried forward as unresolved
gaps (no document gets to retire them by citing itself).

## New findings this round

### 1. Address → map link: different URI scheme, undocumented, untested

- **Upstream**: `tests/core/test-addresses-chunk.vala:50` (`test_to_maps_uri`)
  pins `Contacts.Address#to_maps_uri` to produce `maps:q=Yellow%20brick%20road`
  — the `geo`-style URI GNOME Maps registers for, opened via
  `Gio.AppInfo.launch_default_for_uri`.
- **Port**: `lib/contact_sheet.rb:88` instead opens
  `https://www.openstreetmap.org/search?query=#{URI.encode_www_form_component(address.value)}`
  — a web URL to a different service entirely.
- This is a behaviour substitution (every address row opens a browser tab to
  OSM instead of handing the GNOME Maps app a `maps:` URI), and it is not
  recorded anywhere — not in `component-inventory.md`'s Rows/small-widgets
  table, not in a code comment at `lib/contact_sheet.rb:88`. Per the
  `component-parity` skill, an undocumented substitution is a gap, not a
  correspondence: nobody wrote down *where* the equivalence was decided.
  **Gap.**

### 2. Birthday "today" check is wrong on the exact case upstream tests for

- **Upstream**: `tests/core/test-birthday-chunk.vala:40` (`test_leap_day_birthday`)
  pins that a birthday of Feb 29 counts as "today" on Feb 28 of a
  **non-leap** year (`feb_28_non_leap_year`, asserted true), and does *not*
  count as today on Feb 28 of a leap year (asserted false).
- **Port**: `lib/contact.rb:319-325`
  ```ruby
  def birthday_today?
    @birthday.then do |bday|
      if bday.is_a?(Date)
        Date.today.then { |today| bday.month == today.month && bday.day == today.day }
      end
    end
  end
  ```
  A plain `month == month && day == day` compare. For a Feb 29 birthday, in
  any non-leap year `today.day` can never be 29, so `birthday_today?` returns
  `false` on Feb 28 of a non-leap year — the opposite of what upstream's own
  test requires. The "Their birthday is today! 🎉" banner
  (`lib/contact_sheet.rb:175`) silently never fires for a Feb-29-born contact
  except once every four years.
- `test/test_contact.rb:103-106` (`test_birthday_today`) exercises only an
  exact-date match and a non-matching date; it does not include a Feb 29
  case, so the port's own suite does not catch this. **Gap — a real
  behavioural bug, not just a missing test.**

### 3. `get_absolute_url` equivalent exists but has zero test coverage

- **Upstream**: `tests/core/test-urls-chunk.vala:26` (`test_get_absolute_url`)
  pins three cases: scheme present and https, scheme present and non-https
  (`ftp://`), and no scheme (prepend `https://`).
- **Port**: `lib/contact_sheet.rb:185`
  (`def absolute_url(url) = url.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? url : "https://#{url}"`)
  implements the same idea, including the non-https-scheme-passthrough case.
- No test anywhere in `test/*.rb` calls `absolute_url` (grep for
  `absolute_url` across `test/` returns nothing). Behaviour exists; it is
  unverified. **Gap**, carried into `test-parity.md`.

## Carried-forward gaps from `.reports/component-inventory.md`

These were already on record and are still open; repeating them here so this
report doesn't imply they were resolved:

- `lib/preferences_dialog.rb` — upstream's preferences window lists every live
  EDS address-book source with its own enable/disable toggle; the port shows
  only the single active backend. **Gap** — `component-inventory.md`'s row
  for this was rewritten this round per `accountability-ensurance.md`, since
  the previous "by design" phrasing read as sanction.
- `lib/avatar_selector.rb` — upstream offers a camera/portal avatar source;
  the port has none. **Gap.**
- `lib/qr_code_dialog.rb` — upstream renders the QR with `libqrencode`; the
  port uses `rqrcode_core`. Likely an acceptable substitution (same output
  contract, a QR image of the vCard), but it has never been verified pixel-
  or-decode-equivalent against upstream's renderer. **Unverified, treat as
  gap until checked.**
- App menu / primary menu in `data/ui/contacts-main-window.blp` vs.
  `lib/main.rb` — inventory itself says "needs confirmation against blueprint
  menu model (not yet scanned at widget level)". **Open gap**, not resolved
  by this round either (see `component-identification.md`).
- `src/contacts-esd-setup.vala` — EDS provisioning on first run, "folded
  informally" into `lib/accounts_list.rb`/`lib/setup_window.rb` with no
  dedicated file and an unconfirmed claim that `did-initial-setup` gating
  still matches. **Open gap.**
- `data/icons/**/*.svg` and `data/style.css` — inventory marks both
  "not verified". **Open gap**, zero widget-level CSS-class check has been
  done for any file (consistent with `component-identification.md`'s
  finding that no widget-level inventory exists).

## Verdict

**Not clean.** Two previously unrecorded behavioural gaps (maps URI, leap-day
birthday) plus one untested-but-present behaviour (absolute URL) found this
round, on top of six still-open gaps already on record and never closed.
