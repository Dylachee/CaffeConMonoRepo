# CafeConnect API Contract

Base URL: /api/

## Authentication

Flutter staff app uses DRF token authentication.

- POST /api/auth/token/ returns {"token":"..."}.
- Send Authorization: Token <token> for protected endpoints.

## REST Resources

- GET /api/menu-items/ public read, authenticated write.
- GET /api/tables/ public read, authenticated write.
- GET /api/orders/ authenticated.
- POST /api/orders/ authenticated.
- PATCH /api/orders/{id}/ authenticated.
- GET /api/employees/ admin only.

## Create Order Payload

{"table_id":1,"guest_name":"Alex","notes":"No sugar","items":[{"menu_item_id":1,"quantity":2},{"menu_item_id":3,"quantity":1}]}

## WebSocket

ws://localhost:8000/ws/staff/?token=<token>

Server messages include order.created and order.updated events with the serialized order payload.
