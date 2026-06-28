# CafeConnect — System Design & Production Build Plan

> Translating the "Master Prompt (Production)" into an executable plan against the
> **actual** repository, resolving conflicts with the already-running system, and
> fixing the architecture before mass code generation.

## 1. Current state (ground truth)

- **Repo:** `MonoRepForCafeConn/` (the prompt's `CafeConnectApp/` / `CafeConnectDesign/`
  names are idealized — real dirs are `CafeConn/` and `CafeConnectDesighn/`).
- **Staff app:** `CafeConn/lib/main.dart` (~5.3k lines, working). Provider + Hive +
  go_router + flutter_animate. Already extended with `lib/data/` (ApiConfig, DTOs,
  REST client, WebSocket client) and wired live: login → bootstrap → realtime;
  order create / mark-ready / availability / close-table push to the API
  (optimistic + rollback); guest attention recolors tiles.
- **Backend:** `CafeConnWeb/` — Django 5 + DRF + **Channels** (Postgres + Redis),
  running in Docker. Ships a Flutter-shaped `staff/bootstrap` endpoint, a token-auth
  WebSocket staff feed, and a public `attention-signals` endpoint. **This is already
  the realtime hub the prompt's Phase 8 asks us to build.**
- **Design source of truth:** `CafeConnectDesighn/CafeConnect Staff.dc.html`
  (+ `Гость`, shots, `refs/mockups.pdf`).

## 2. Conflicts to resolve BEFORE mass build

| # | Prompt says | Reality | Recommendation |
|---|-------------|---------|----------------|
| 1 | Build a **new Dart `shelf`** backend on `:8080` | Django + Channels hub already runs and is purpose-built for this app | **Keep Django.** Wrap the existing client in a `RealtimeHub` abstraction. Do **not** stand up a second backend (two sources of truth, double the ops). |
| 2 | `CafeConnectApp/`, `CafeConnectDesign/` | `CafeConn/`, `CafeConnectDesighn/` | Use the real paths. |
| 3 | Full `lib/core/...` rebuild of the monolith | Working 5.3k-line monolith + `lib/data/` | **Incremental extraction** — app compiles at every step. No big-bang rewrite. |
| 4 | `TableStatus { free,newOrder,occupied,ready,late }` (5) | App + backend also have **`awaitingPayment`** (Счёт/bill) | Keep **6** states; dropping it loses the bill flow. |
| 5 | JetBrains Mono "already bundled" | Only **Inter** is in `assets/fonts/` | Add the ttf to activate (mono styles already wired with Inter fallback). |
| 6 | Guest app = Flutter Web **or** HTML | The design **is** HTML; Django can serve it | **Serve a static guest page from Django**, wired to the existing attention API/WS. |

## 3. Target architecture (recommended)

```
   ┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
   │ Staff (Flutter)   │ Guest (web/QR) │     │ Mgmt dashboard   │
   │ CafeConn/         │ served by Django     │ (Django templates)│
   └──────┬──────┘     └──────┬───────┘     └────────┬─────────┘
          │  REST + WS (token)        │ REST + WS (public attention)│
          └───────────────┬──────────┴─────────────┬──────────────┘
                          ▼                         ▼
                 ┌────────────────────────────────────────┐
                 │  Django + DRF + Channels (CafeConnWeb)  │
                 │  Postgres (state)   Redis (WS fan-out)  │
                 └────────────────────────────────────────┘
```

Flutter side gets a thin `RealtimeHub` interface with two implementations —
`MockRealtimeHub` (offline/demo + Settings dev-triggers) and
`WebSocketRealtimeHub` (wraps the existing `CafeApiClient` + `StaffRealtimeClient`).
This satisfies the prompt's hub abstraction **without** a new server.

## 4. Phase mapping (prompt → reality)

| Phase | Prompt scope | Status today | Plan |
|-------|--------------|--------------|------|
| P1 Design system | tokens + widgets in `lib/core` | tokens exist in monolith and match | extract to `lib/core/theme`; add `bill` color + mono |
| P2 State + Hive | immutable models, persists | exists & persists | align to `copyWith` incrementally |
| P3 Tables | pixel-perfect grid | exists; attention recolor done | colorTag bar, dot pulse, reels long-press |
| P4 Table detail | full | exists | item-editor sheet, change calc, "готово на кухне" chip |
| P5 Menu + precheck | full | exists; send wired to API | finish select-mode + auto-split preview |
| P6 Orders/Chats/Panel/Settings | full | exist; Settings connection done | menu-mgmt real content, order timers/priority |
| P7 Guest web | new | not started | static page on Django |
| P8 Backend | new Dart server | **already done via Django** | reuse; gap-fill endpoints only |

About half the "8 phases" are already satisfied by what exists + what's been built.

## 5. Trade-offs

- **Keep Django vs new Dart server:** reuse a working realtime hub and keep one
  source of truth; we lose the "one language" tidiness — acceptable since the
  backend is already done and richer than the proposed shelf server.
- **Incremental vs big-bang refactor:** incremental keeps the app runnable and
  reviewable each step; it's slower than a clean rewrite, but a blind 5.3k-line
  rewrite (no compiler in the build env) would almost certainly break the app.
- **Guest as HTML-on-Django vs Flutter Web:** faster, pixel-faithful to the design
  file, reuses the backend; not a single Flutter codebase.

## 6. Execution order (after decisions)

1. Extract design system → `lib/core/theme` (+ `bill` color, mono) — keeps compiling.
2. `RealtimeHub` abstraction over existing clients + Settings dev-triggers.
3. Screen-by-screen fidelity P3 → P6 (each independently shippable).
4. Guest page on Django (P7).
5. Backend gap-fill only as needed (P8).

## 7. Risks

- No `flutter analyze`/`build` in the agent sandbox → you run after each step, I fix.
- Large monolith → edits stay surgical; a full rewrite would break the running app.
- Git discipline: local edits only; the user reviews and commits.
