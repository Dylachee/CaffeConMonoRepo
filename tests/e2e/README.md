# CafeConnect E2E Tests

These tests are black-box Playwright tests for the approved CafeConnect flows.

## Local Run

Start the Django stack from `CafeConnWeb/`, then seed deterministic E2E data:

```bash
cd CafeConnWeb
docker compose up -d
docker compose exec web python manage.py migrate
docker compose exec web python manage.py seed_e2e
cd ..
npm install
npm run e2e
```

Override the target server when needed:

```bash
E2E_BASE_URL=http://127.0.0.1:8000 npm run e2e
```

## Test Data

`seed_e2e` only touches isolated rows:

- users: `e2e_manager`, `e2e_waiter`, `e2e_kitchen`, `e2e_bar`
- password: `CafeConnectE2E!`
- tables: `901`, `902`, `903`
- menu rows prefixed with `E2E`

It deletes orders and attention signals only for the E2E tables.

## Current Coverage

Executable tests currently cover:

- environment/smoke
- guest menu navigation, language switch, category filtering, detail/cart flow
- guest order approval and rejection
- order-level notes in guest/staff API surfaces
- station split, ready, and separate delivery state
- attention/call waiter and bill request
- role/permission API gates
- menu availability/stop-list visibility

Next phase:

- direct Flutter web table grid automation
- direct Flutter web order composer automation
- settings connection/logout/persistence flows
- manager panel UI automation
- websocket-only realtime assertions without refresh
- negative UI cases: invalid QR, network errors, double-submit, refresh/back
