# CafeConnect Finance — backend integration plan

Turning the standalone prototype (`index.html`) into a real owner/accountant surface on
the existing Django backend (`CafeConnWeb/apps/core`, `apps/api`). Written against the
current models; each tier lists exactly what already exists vs. what must be added.

## What the backend already gives us (no schema change)

- `Order` — `status` (incl. `PAID`), `source`, `employee` FK, `table` FK, `created_at`
  (indexed), `total` property (sum of `OrderItem.line_total`).
- `OrderItem` — `line_total`, link to `MenuItem`.
- `MenuItem` — `name`, `price`, `category`, `station`.
- `Employee` — `role` (already includes `ACCOUNTANT`, `MANAGER`, `ADMIN`), `is_on_shift`.
- `OrderEvent` — timestamped action log.

So **Overview** (revenue, order count, average check, revenue trend, top dishes) is fully
derivable **today** from `Order` filtered to `PAID`/`COMPLETED` within a date range +
`OrderItem` rollups. That is the honest MVP and should ship first.

## Gaps that block the other views (must be added)

| View | Blocking gap | Fix |
|------|-------------|-----|
| Payment mix (donut) | No payment method stored on `Order` | Add `Order.payment_method` (`cash`/`card`/`qr`), captured at "Libera tavolo"/pay |
| Gross margin / COGS / P&L | `MenuItem` has `price` but **no cost** | Add `MenuItem.cost` (or a per-category cost ratio table) |
| Payroll | `Employee` has no pay rate; only `is_on_shift` boolean, no clock times | Add `Employee.hourly_rate`; add a `Shift` model (`employee`, `opened_at`, `closed_at`) |
| Taxes | No tax regime/rates stored | Add a `TaxConfig` (jurisdiction, regime, rate rows, due-day rules) — **needs the locale decision below** |
| Export | Nothing generates files | Server-side CSV/XLSX/PDF builders; R-Keeper sync is a separate spike |

## Locale / jurisdiction — decide before Taxes is real

The staff app is Italian; the prototype is Russian with a Russian regime (УСН, взносы,
НДФЛ) and `$` amounts. Tax logic is country-specific and can't be faked. Pick the
jurisdiction + currency once, store it in `TaxConfig`, and drive both the Taxes view and
number formatting from it. Until then, Taxes stays demo.

## Auth — separate surface, reuse the role model

PRODUCT.md wants a separate web login. `Employee.Role.ACCOUNTANT` already exists and
`capabilities['manage']` is boss-only. Add a `finance` capability (owner/admin +
accountant + optionally manager), gate a new `/finance/` route + `/api/finance/*` on it.
Do **not** expose finance data to the waiter token.

## Proposed endpoints (mirror the existing bootstrap pattern)

One aggregation endpoint returns the whole dashboard payload for a period, so the client
stays the thin renderer it already is:

```
GET /api/finance/summary?period=week            # or ?from=YYYY-MM-DD&to=YYYY-MM-DD
  -> { period, generated_at,
       kpis:  { revenue, net, margin, ebitda, avg_check, orders, breakeven },
       trend: [{ label, revenue }],
       breakdown / pnl: [{ label, amount, pct }],
       dishes:  [{ name, qty, revenue }],
       payments:[{ method, pct }],
       payroll: [{ employee, role, hours, rate, gross, tips, held, net }],
       taxes:   [{ name, base, rate, amount, due, status }] }
GET /api/finance/export?period=&format=csv|xlsx|pdf&include=rev,pnl,pay,tax
```

`generated_at` powers the "Данные на …" freshness stamp already in the header.

## Sequencing

1. **Overview, real** — `/api/finance/summary` KPIs + trend + top dishes from `PAID`
   orders; wire the client's period switch to it. (No schema change.) `/impeccable onboard`
   for empty/first-café states.
2. **Payment mix + real COGS** — add `Order.payment_method` and `MenuItem.cost`; donut and
   P&L gross line become real.
3. **Payroll** — `Employee.hourly_rate` + `Shift` clock-in/out (the prototype's own note
   already flags this as the prerequisite).
4. **Taxes + Export** — `TaxConfig` after the locale decision; CSV/XLSX/PDF builders;
   R-Keeper API feasibility spike (interim: file export, which the UI already frames).
5. **Auth surface** — `finance` capability + gated route/login.

## Prototype status

`index.html` is now internally consistent (all views derive from the selected period) and
carries a visible **демо-данные** marker + freshness stamp so it never reads as live.
</content>
</invoke>
