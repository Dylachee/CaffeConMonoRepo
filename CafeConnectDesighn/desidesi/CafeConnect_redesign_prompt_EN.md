# CafeConnect — Staff POS Redesign: Full Implementation Prompt (v2)

You are a senior product designer + Flutter engineer. You are improving **CafeConnect**, a staff-only POS app for a café/restaurant (waiters, kitchen, bar, managers, admin — **no customer-facing app, no QR**). A strong HTML/React prototype already exists and is genuinely good: warm, calm, fast, iOS-grade. Your job is to implement the feature set below **and** to raise the bar wherever your own UX judgment sees an opportunity. The prototype is a reference, not a ceiling — if you can make a flow faster or clearer for a waiter, do it.

**North star:** speed and clarity for a waiter on the floor. No action should cost more than 2–3 taps. Minimal, clean, modern. Don't overload any screen.

---

## 1. Visual system (keep this — it works)

- **Background:** warm cream `#F2EFE8`. **Surfaces:** white `#FFFFFF`. Sunken/segment backgrounds `#EBE6DB`.
- **Text:** ink `#1E1B16`, secondary `rgba(30,27,22,.55)`, tertiary `rgba(30,27,22,.40)`. Hairlines `#E7E2D8`.
- **Primary action color = espresso `#221F1A`** (buttons, active nav, send). **Never blue for buttons** — blue is reserved as a *zone* color.
- **Zone colors (semantic only):** Kitchen = orange `#E0823A`; Bar = blue `#3C7BCF`. Status: ok/ready `#3E9C63`, warn/new = orange, late/danger `#D9564A`, gold/manager `#B98A3C`. Tables: free `#B8B1A3`, occupied `#5B86B0`.
- Pills/badges use a 12–14% tint of their semantic color as background.
- **Shape:** radii — cards 18–20, buttons 14, sheets 24 (top corners), chips 10–11, tables 20, avatars 14 (squircle, **not** circles).
- **Soft shadows** (no flat): `0 1px 2px rgba(43,36,24,.05), 0 10px 22px -15px rgba(43,36,24,.22)`.
- **Type:** Inter for UI; **JetBrains Mono / RobotoMono for receipt lines, timers, prices, change** (gives a real "check" feel).
- Press feedback: scale ~0.97 + spring; `HapticFeedback` on every commit (see §10).
- Bottom tab bar (frosted): **Tables · Orders · Menu · Chats · Panel**, with badges (late-orders count on Orders, unread count on Chats).

---

## 2. Tables screen

- Header: title "Столы", subtitle "Zone 1 · N active · M free". Two header buttons: **+ (add table, espresso filled)** and **filter**.
- Search by table number or waiter. Horizontal status legend/filter chips (All / Free / New / Occupied / Ready / Late) with colored dots; active chip = espresso.
- Grid of soft white table cards (3 cols default, 4 optional): big number, status dot with halo (pulse for New/Ready, blink for Late), status pill, order total (or "free"). **Optional color tag** = a small colored bar at the card's top edge when the table has a zone/label assigned.
- **Gestures (critical):**
  - **Tap** → open Table Detail (§3).
  - **Long-press** → "Reels-style" full-screen quick **Check** preview (zoom/pop animation, receipt look, dim+blur backdrop), release to close. From it: "Forward" or "Open table".

## 3. Table Detail (tap) — editable order, the heart of the app

Full-screen sub-screen with a back arrow and a small **edit-table** (pencil) button in the header.

- **Current order card** = the active check. **Every line is editable** with minimal taps:
  - Tapping a line opens an **item bottom sheet**: quantity stepper, **editable unit price**, a **free-text note** (allergies, doneness, "no onion"), and a **Remove** button. (Bottom sheets are strongly preferred over center modals — but if you find a faster inline pattern for a waiter, use it.)
  - Item notes render under the item name in amber.
  - A dashed **"+ Add item"** button opens a quick dish picker (grouped, zone-colored) that appends to the order.
  - Line total + grand total in mono.
- **Change calculator card:** waiter types cash given → shows change due (green) or shortfall (red), mono. Fast mental-math helper at the table.
- **Table notes:** amber chips + an input to add notes that belong to the whole table (VIP, birthday, allergy).
- **Status editor:** row of status pills (Free / Occupied / New / Ready / Late) updating the table state.
- **Actions:** "Forward" (Telegram-style, §6) and "Show check" (Reels preview).

## 4. Menu — Select & Precheck (iOS-Photos pattern)

Two modes on one tab:

**Browse mode (default):** category chips (first level) → item cards (second level), search. Cards show photo, prep-time badge, zone dot, price, availability ("In stock" / "Stop-list" with dimmed overlay). Tap a card → reference sheet with photo, composition, allergens, prep time, availability (so a waiter can describe a dish to a guest). Fast navigation is a priority.

**Select mode (toggle "Select" in header):**
- Cards become selectable like iOS Photos: a check circle appears; selected cards get an espresso ring + per-card **quantity stepper**.
- A **bottom bar** appears: count + running total + **"Precheck"** button. ("Reset" clears.)
- **Precheck sheet** (resembles the final receipt — clean, mono, with total):
  - **Table picker** at top (choose which table this order is for).
  - Receipt rows, each with an inline **per-item note field** (allergies, doneness…).
  - **Auto-split preview:** two tiles showing how many items go to **Kitchen** vs **Bar**.
  - Big send button → "Send to Table NN".
- On send: items are appended to that table's order, table flips to "New", and a toast confirms the **automatic split** ("Sent → Kitchen 2 · Bar 1"). Routing food→kitchen / drinks→bar must be transparent: the waiter taps Send, the system routes. (In the real app, create the two station tickets here.)

## 5. Table management

- **Add table** (+ on Tables): bottom sheet with number/name, **seats** stepper, and a **zone/label color** swatch picker (squircle swatches with check on selection).
- **Edit table** (pencil in Detail header, or long-press menu): same fields + a **Delete** (trash) button.
- Keep it minimal — no clutter.

## 6. Forward (Telegram-style)

Bottom sheet: a forwarded **table card** preview (left color bar, items, total, "card opens on tap"), an optional comment, and a "WHERE TO SEND" list (Kitchen / Bar / General chat / specific staff, squircle avatars + send button). Sending posts an **interactive table card** into that chat and navigates there. The chat card has a "Open table" button that deep-links back to Table Detail. (Same mechanic already exists for order cards.)

## 7. Orders feed (Kitchen / Bar)

Segmented control (frosted pill, zone dot + count). Order cards: top 4px zone strip, table badge, "#id · zone", **mono live timer** (green <15m, orange 15–20m, red >20m; late cards get a soft danger border pulse), item lines (qty in zone color), "Mark ready" (espresso → green "Ready ✓"), and a "discuss in chat" icon button.

## 8. Panel = Admin + Manager merged

One screen, 4 segments: **Overview · Team · Menu · Access.**

- **Overview:** 2×2 metric cards (revenue, average check, active tables N/12, avg prep time + late count) with deltas; a **revenue-by-hour bar chart** (use explicit pixel bar heights, not %, so bars don't collapse).
- **Team:** role filter chips; staff rows (squircle initials in role color, name, role·status, online dot, edit pencil); **"Add staff"** → bottom sheet (name + role chips). *(Keep Team as-is per stakeholder — it's liked.)*
- **Menu (management) — redesigned, NO photos:** compact list rows: zone dot, name, "zone · category", a tappable **price chip (opens edit)**, and an **availability toggle** (green = in stock, grey = stop-list, instantly affecting the storefront and kitchen stop-list). **"Add item"** and edit use a **bottom sheet**: name, free-text composition, price, station (Kitchen/Bar), availability toggle. Photo is optional — text alone is fine.
- **Access:** role cards (Waiter / Cook-Bar / Manager / Admin) with permission chips (granted = green, denied = grey), tap to toggle.

## 9. Chats, offline, dark theme

- Chats: squircle zone avatars, unread badges, pinned. Dialog: own bubbles espresso, others white; supports **interactive order cards and table cards**.
- **Offline indicator:** red frosted banner ("No network · orders will sync later"); queue locally, auto-send on reconnect with a success toast.
- **Dark theme** (at least scaffolded): bg `#17150F`, surface `#201C15`, line `#2E2920`, ink `#F4F1EA`; zone/status colors unchanged. Persist theme choice.

## 10. Feedback (haptics + optional sound)

`HapticFeedback`: long-press check = medium; status change / mark-ready / send = selection + light; new kitchen ticket = medium + soft ping; >20m late = one heavy + warning sound; message/forward = selection; stop-list toggle = selection. All sounds quiet and toggleable.

---

## 11. Flutter architecture notes (existing project)

Stack: Flutter (Material 3 + Cupertino), Provider (`CafeState`), GoRouter, Hive, google_fonts (Inter), flutter_animate. Currently a monolithic `main.dart` with a `MockCafeApi`.

- Centralize tokens in an `AppColors` `ThemeExtension` (light + dark); replace every legacy color — especially **kill all blue buttons → espresso**, and fix any white-on-white text.
- Reusable widgets: `AppButton` (espresso / secondary / ghost), `AppCard`, `StatusBadge`, `CategoryChip`, plus new `TableCard`, `OrderCard`, `MetricCard`, `ForwardCard`, `NoteChip`, `ItemEditSheet`, `PrecheckSheet`, `TableEditSheet`.
- Models: table = `{number/name, seats, status, colorTag, waiter, openedAt, notes[], order[]}`; order item = `{name, qty, price, note}`; message kinds = `{text, orderCard, tableCard}` (table cards store a snapshot so the forwarded check doesn't drift).
- Auto-login straight to **Tables** (no login screen in the default route; keep it reachable for "switch user"). Remove all customer/QR/cart/customer-status code.
- Persist tables, menu overrides, notes, theme, and the offline queue in Hive.
- Prefer **bottom sheets** (`showModalBottomSheet`, rounded top, drag handle) for item edit, add/edit table, add staff, menu edit, forward, precheck; use a Reels-style `showGeneralDialog` (scale+fade) only for the long-press check preview.

## 12. You are encouraged to improve

Where you see a faster or cleaner path for the waiter, propose and implement it — e.g. swipe actions on table/menu/order rows, a "split bill" affordance in the check, a one-tap "repeat last round", smarter table-picker defaults (nearest free table), keyboard-less number entry for change, or batched haptics. Keep every addition minimal and justified — when in doubt, fewer taps and less chrome win. Build the whole thing as one cohesive, fast, beautiful staff app.
