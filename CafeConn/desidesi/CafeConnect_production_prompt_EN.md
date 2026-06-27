# CafeConnect — Production Build Prompt (v3, staff app)

> **Your role.** Senior product designer + Flutter engineer finishing **CafeConnect**, a **staff-only** café/restaurant operations app (waiters, kitchen, bar, managers, admin). A strong, warm, iOS-grade prototype already exists and is genuinely good — extend it, don't reinvent it. All UI copy is **Russian**. Build everything so it's fast and clear for a waiter on the floor: **no action over 2–3 taps**, bottom sheets over center modals, optimistic updates (never block on a spinner).
>
> **Reference design:** `CafeConnect Staff.dc.html` (this prototype) + `CafeConnect_redesign_prompt_EN.md` (v2 base). This document is the production layer on top of them.

There is a **separate client web app** (guests scan/меню/«позвать официанта») that is **out of scope** — you build only the **staff-side receiver** of its signals and the documented event contract (Part 4). Do not add a client ordering flow, cart, or QR to this app.

---

## 1. Design system (keep — do not introduce a second style)

- Warm cream bg `#F2EFE8`, white surfaces, sunken `#EBE6DB`. Text ink `#1E1B16` / `.55` / `.40`. Hairline `#E7E2D8`.
- **Primary action = espresso `#221F1A`** (buttons, active nav, send). **Blue is never a button** — it's a zone/status color only.
- **Zone colors:** Kitchen orange `#E0823A`, Bar blue `#3C7BCF`. **Status:** ok/ready `#3E9C63`, new/warn = orange, late `#D9564A`, gold `#B98A3C`.
- **Attention/arrival states (new):** arrived/seated `#3E78C9` (blue), call-waiter `#E0823A` (amber), bill-requested `#8A6FC0` (purple), free `#B8B1A3`. Each tint at ~14–16% for pill backgrounds.
- Radii: cards 18–20, buttons 14, sheets 24 (top), chips 9–11, tables 20, avatars 14 (squircle). Soft shadows (`0 1px 2px rgba(43,36,24,.05), 0 10px 22px -15px rgba(43,36,24,.22)`). Inter UI; **JetBrains/RobotoMono** for receipts, timers, prices, change, quantities.
- Press feedback scale ~0.97 + spring; haptics on every commit.
- **Accessibility — never rely on color alone:** every status/attention state also carries an **icon + text label** (arrived=person, call=bell, bill=receipt). A **High-contrast** setting strengthens borders and removes color-only cues.
- Bottom tabs: **Столы · Заказы · Меню · Чаты · Панель** with badges (late-orders on Заказы, unread on Чаты). Settings («шестерёнка») opens from the Панель header.

---

## 2. State model (extend existing Provider `CafeState`)

```
Table { id, number/name, seats, guestCount, status, colorTag,
        attention: null|'arrived'|'call'|'bill', attentionReason, ack:bool,
        waiter, openedAt, notes:[String], currentOrderId }
Order { id, tableId, items:[OrderItem], status, createdAt, updatedAt }
OrderItem { id, dishId, name, qty, price, notes:[String],
            station:'kitchen'|'bar', ready:bool, done:bool }   // ready = made at station; done = delivered to table (distinct!)
AttentionSignal { tableId, type:'arrived'|'call_waiter'|'bill_request', reason?, createdAt }
Prefs { soundArrival, soundCall, soundBill, haptics, volume,
        sortUndelivered, showReady, confirmClear, theme, textSize, highContrast }
```

**Status vocabulary (single source):** order `new → cooking → ready → delivered → paid`; item `ready` (station) and `done` (delivered) are independent booleans.

**Critical rule:** every staff mutation (toggle done, guest ±, add note, send order, ack signal, stop-list) is **optimistic** — update local state immediately, emit through the service interface, reconcile on server confirm, revert + toast on failure. Keep `MockCafeApi` / `MockRealtimeHub` behind interfaces so real REST/WebSocket swaps in with zero UI changes.

---

## 3. THE FEATURES (all implemented in the prototype — match them, then improve)

### 3.1 Inline guest count (table card)
On the open table card, a compact **− value +** stepper sets `guestCount` instantly (emit event). Min 1; **soft warning** (toast, not a block) when it exceeds `seats`.

### 3.2 Delivered toggle + strikethrough («прочерк»)
Each order line on the table card can be marked **delivered/undone**:
- **Long-press** the line toggles `done` (chosen so scrolling never mis-toggles); a **leading checkbox** offers the same (and teaches it); plain **tap** opens the item editor.
- Done = strikethrough name + filled check + de-emphasized (40% opacity), notes greyed but still visible.
- Header shows **«X/Y отдано»**; a **«Неотданные сверху»** sort toggle floats outstanding items to the top.
- `ready` (made at station) is shown distinctly from `done`: a small green **«готово на кухне/баре»** chip on items the station marked ready but the waiter hasn't delivered. Haptic on toggle.

### 3.3 Multi-note items («примечание») + presets
- A line carries **multiple removable note chips**. Add via a **«+ примечание»** affordance on the line → item sheet with **one-tap presets** (Без лука, Без льда, На соевом, Остро, Не остро, Навынос, Без сахара, Хорошо прожарить…) + free text.
- Notes are addable on **both** client (dish sheet/cart — in the separate app) and **staff** (table line) sides; they **propagate to the correct station** and show on the kitchen/bar order feed (an unmodified item reaching the cook with no note is the failure mode to design against).
- Notes survive the delivered/strikethrough state (greyed, still readable). Whole add-note flow is an inline sheet, never a new screen.

### 3.4 Item editor (tap a line)
Bottom sheet: qty stepper, **editable unit price**, multi-note manager (chips + presets + free text), **Remove**, Save (shows live line total).

### 3.5 Menu Select & Precheck (iOS-Photos pattern)
Browse mode (categories → items, search, reference sheet with состав/аллергены/время). **Select mode**: tap to select (check circle + per-card qty stepper) → bottom bar **«Пречек N · total»** → precheck sheet (receipt look) with a **table picker**, per-item note fields, and an **auto-split preview** (Кухня X / Бар Y). Send appends to that table's order, flips it to «Новый», routes food→kitchen / drinks→bar automatically, toast confirms the split. 2–3 taps total.

### 3.6 Table management
**Add** (+ on Столы): number/name, seats stepper, color/zone swatch. **Edit** (pencil in detail header): same + **Delete**. Bottom sheets, minimal.

### 3.7 «Client arrived» / attention — staff-side receiver (the integration core)
- Table tiles recolor by `attention`: free=grey, **arrived=blue (pulsing dot until ack)**, **call=amber**, **bill=purple** — each with icon + label, never color alone.
- A new incoming signal fires a **tappable toast** («Стол NN зовёт официанта») + (designed) sound + haptic; tapping opens that table. In the table detail an **attention banner** shows reason + **«Принял»** (ack → pulse stops, `ack:true`, color stays) and, once acked, **«Принято»** → clears.
- A **dev test-trigger** (Settings → Соединение) simulates an incoming arrival/call/bill so the flow is demonstrable before the backend exists.

### 3.8 Settings («шестерёнка») — make it real
Apple-style grouped screen, all persisted, live: **Профиль** (user, role, Выйти) · **Уведомления** (sound per signal, haptics, volume) · **Карточка стола** (sort-undelivered default, show «готово на кухне», confirm-clear) · **Внешний вид и доступность** (тема light/dark, размер текста S/M/L, **высокий контраст**) · **Соединение** (realtime status + Переподключить + read-only server URL + dev trigger) · **О приложении** (version/build).

### 3.9 Panel = Admin + Manager
Segments **Обзор · Команда · Меню · Доступ**. Overview = 2×2 metrics + revenue-by-hour bars (explicit px heights). Team kept as-is (liked) + add-staff sheet. **Menu management is photo-less**: compact rows (zone dot, name, zone·category, tappable price chip → edit, availability toggle = stop-list); add/edit via bottom sheet (name, free-text composition, price, station, availability — photo optional). Access = permission chips per role.

### 3.10 Orders feed, Chats, Offline
Zone segmented control; cards with zone strip, mono live timer (green<15m / amber 15–20 / red>20 + pulse), **item notes shown to the station**, «Отметить готовым» → green «Готово ✓». Chats: zone avatars, unread badges, **interactive order AND table cards** (forward, deep-link to detail). Offline: red frosted banner, queue locally, auto-sync on reconnect.

---

## 4. Realtime integration (build this seam now)

Define one interface and back it with mocks today:
```dart
abstract class RealtimeHub {
  Stream<AttentionSignal> get attentionStream;   // staff app only listens
  Future<void> ackSignal(String tableId, String signalId);
}
```
**Event contract (the only thing the separate client app must agree on):**
- attention → `{ tableId, type: "arrived"|"call_waiter"|"bill_request", reason?, createdAt: ISO8601 }`
- ack → `{ tableId, signalId, ack:true, by:staffId, ackedAt }`

**Transport: WebSocket (recommended) with REST-polling fallback.** The client app publishes a signal → backend pushes over socket → staff app raises flag, recolors tile, fires toast. WebSocket is correct because the whole value is **immediacy** and it supports clean `ack` round-trips; REST polling is only a degraded fallback (latency = interval, battery cost, no real ack). Implement so the socket client transparently falls back to short polling on drop and re-upgrades on reconnect — **the UI only ever listens to `attentionStream`** and never knows the transport. The Settings → Соединение row reflects the live transport (socket/polling/offline).

---

## 5. Production-ready checklist
1. Guest count inline (±, soft cap warning, persisted, event-emitted).
2. Long-press + checkbox delivered toggle with strikethrough/check/haptic; «X/Y отдано»; undelivered-first sort; `ready`≠`done` shown distinctly; station «mark ready» propagates live.
3. Multi-note items (presets + free text, removable), addable client+staff, propagated to the right station, surviving strikethrough.
4. Simulated arrival recolors the right tile + toast/sound/haptic + «Принял» ack + tap-to-open — all through one `RealtimeHub` stream a WebSocket (REST fallback) implements unchanged; event shapes documented.
5. Settings screen fully working & persisted (profile, notifications, table-card prefs, appearance/accessibility incl. high-contrast + color-blind-safe icon labels, connection status, about).
6. Every screen has empty/loading/error/offline states; all mutations optimistic with reconciliation; no hardcoded English; copy centralized for i18n.
7. App runs end-to-end on mocks; real REST/WebSocket swaps in with no UI change.

## 6. Out of scope / leave alone
Don't build the separate client web app (only the staff receiver + contract). Don't redesign the visual system, rename components, or change the role model. You **may** propose small UX wins (swipe actions on rows, split-bill, repeat-last-round, nearest-free-table default, keyboardless change entry) — flag them as optional and keep every addition minimal: fewer taps, less chrome.
