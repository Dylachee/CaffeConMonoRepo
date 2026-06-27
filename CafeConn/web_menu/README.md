# CafeConnect Menu Template

A mobile-first restaurant menu template inspired by the provided design references.

## Run

Open `index.html` in a browser.

For table URLs such as `/1`, `/2`, or `/3`, run:

```bash
node server.mjs
```

Then open `http://localhost:4173/1`. The same menu is shown, but the table number and order payload use that table.

## API switch

The app currently uses mock data. When your backend is ready, edit `app.js`:

```js
const CONFIG = {
  tableId: readTableId(),
  useMockApi: false,
  apiBaseUrl: "https://your-api.example.com",
};
```

Expected endpoints:

- `GET /api/menu`
- `POST /api/orders`
- `GET /api/orders/:id`
- `POST /api/waiter-call`
- `POST /api/bill-request`
- `POST /api/menu/:id/like`

The mock menu data lives in `MOCK_MENU` and can be replaced or extended at any time.
