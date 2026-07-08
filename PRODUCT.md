# Product

## Register

product

## Users

The **café owner** and their **accountant** (back office), not floor staff. They sit
with a laptop, reviewing money: how much came in, where it went, what's owed, who
gets paid. Context is deliberate and periodic (end of shift / week / month / quarter),
not the fast, one-handed, in-the-weeds context of the waiter app. They need to trust
the numbers and to get data *out* (for filing, for R-Keeper, for the accountant's own
tools).

## Product Purpose

CafeConnect Finance is the owner/accountant web console for one café. It turns the
data the floor app already captures (orders, items, payments, per-waiter sales,
action log) into a real financial picture — revenue trend, net profit, margin/EBITDA,
where revenue goes, top dishes, payment mix, **payroll**, **taxes owed**, and
**export** to accounting systems (R-Keeper is the one in use; sync feasibility is
still unknown, so CSV/Excel/PDF export is the interim path). Success: the owner opens
it and, within seconds, knows the health of the business and can hand the accountant a
clean file — without exporting spreadsheets by hand or trusting a gut number.

It is a **separate web surface with its own owner/accountant login**, on the same
backend as the staff app — not a screen inside the waiter app.

## Brand Personality

A **digital ledger** — warm, precise, quietly confident. Same family as the CafeConnect
staff app (Inter + JetBrains Mono, warm cream paper, espresso ink, one green for
"good"), but calmer and more editorial because it's money: understated, trustworthy,
never flashy. Three words: **precise, warm, trustworthy.** Numbers are the loudest
thing on the page; chrome recedes.

## Anti-references

- The **generic SaaS analytics dashboard**: gradient hero-metric cards, purple/indigo
  accents, identical icon+stat card grids, a chart just to have a chart.
- **Cold fintech** (navy-and-gold, terminal-green-on-black). This is a warm café, not a
  trading desk.
- Spreadsheet-grey density with no hierarchy. Dense ≠ dull; every table still has a
  clear read order and a "so what".
- Anything that feels like a *different product* from the staff app — it must read as
  the same brand, one register quieter.

## Design Principles

- **The number is the hero.** Money leads; labels, chrome, and decoration serve it.
- **One family, quieter register.** Reuse the staff app's tokens and voice; dial down
  saturation and motion because this is a back-office, trust-first surface.
- **Trust through precision.** Aligned figures (tabular/mono numerals), honest deltas,
  visible period and source. No rounded-away detail on money.
- **Dense but calm.** Payroll and tax tables are inherently busy; earn calm with
  rhythm, alignment, and restraint, not by hiding data.
- **Get data out.** Export is a first-class action, not an afterthought — the owner's
  job half-ends in the accountant's tools.

## Accessibility & Inclusion

WCAG AA. Body text ≥4.5:1 on the cream surface (bias toward espresso ink, not light
gray). Never encode meaning by color alone — profit/loss and paid/overdue carry an
icon or label too (color-blind safe). Full `prefers-reduced-motion` alternative.
Interface language is Russian (primary), matching the mockup; keep copy translatable.
