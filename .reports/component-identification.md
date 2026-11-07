# Component identification — gnome-contacts-rb vs. origin/main

Scope: both trees in this one repo. Upstream read via `git show origin/main:<path>`
and `git ls-tree -r --name-only origin/main` (never checked out). Port read from
the working tree on `ruby`.

## What already exists

`.reports/component-inventory.md` is a **file-level** map: for every upstream
`.vala`/`.blp` file it names the `lib/*.rb` file that is supposed to carry it,
with a `done` / `partial` / `missing` status. That document exists and is not
wrong as far as it goes.

## The gap in the identification itself

The `component-identification` skill's definition of "identified" is five
facets per widget — **type, CSS classes, signals, actions, owner** — scanned
per file, not per app. `component-inventory.md` never descends past the file
level: it does not enumerate, for any one `lib/*.rb`, the `Gtk`/`Adw` widget
types it instantiates, their counts, the CSS classes applied to them, the
signals connected, or the actions installed/targeted, against the matching
upstream `.vala`/`.blp` pair.

Concretely, none of the following — all required by Step 1–3 of the skill —
exist anywhere in `.reports/`:

- A widget-by-widget count (e.g. how many `Adw.ActionRow`s does
  `data/ui/contacts-contact-pane.blp` build vs. how many does
  `lib/contact_pane.rb` build).
- A CSS-class listing per widget (`styles ["flat"]` in the `.blp` vs. whatever
  `.add_css_class` calls — or their absence — in the matching Ruby file).
- A signal/action listing per widget (`clicked => $on_x()` vs. the Ruby
  `signal_connect`/`g_action_map` calls).

This is not a claim that the five-facet inventory would find more gaps than
listed below — it is the finding itself: **the identification step the other
four skills are supposed to build on was never run at the required
granularity.** `component-parity.md` in this round had to re-derive two
concrete discrepancies (below) from source reading rather than from a prior
inventory, because no inventory at widget granularity exists to consult.

## Upstream unit list (for reference)

Declarative files are the free unit list per the skill. Upstream ships 9
`data/ui/*.blp` templates plus `data/ui/contacts-main-window.blp`, each a
`<template>`-style blueprint root, each mapped 1:1 in `component-inventory.md`
to one `lib/*.rb` file. The port, per house style, has zero `.blp`/`.ui` files
of its own — expected, not a gap (see `component-parity` skill's list of
non-failures).

## Verdict

`component-identification` is **incomplete**: a file-level map exists, a
widget/CSS/signal/action-level inventory does not. See `component-parity.md`
for the two concrete behavioural discrepancies this round's deeper reading
found despite that gap, and treat the absence of the fuller inventory as a
standing gap in its own right, not a formality.
