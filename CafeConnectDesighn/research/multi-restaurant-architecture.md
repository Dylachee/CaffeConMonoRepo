# Multi-restaurant architecture research

## Decision

Use one application deployment and one PostgreSQL database with a shared schema. Add a required `restaurant_id` foreign key to every restaurant-owned row and enforce restaurant scope at every boundary.

This is row-based multi-tenancy. It is the smallest operationally safe design for a handful of restaurants and fits the existing Django application. Do not create one server, schema, or database per restaurant yet.

## Account and authorization model

- `PlatformOwner`: the developer account. It can list and enter every restaurant, create restaurants, and manage restaurant memberships. This should be a platform-level flag or permission, not an employee role copied into every restaurant.
- `RestaurantMembership`: links a user to one restaurant and holds that restaurant's role preset plus effective capabilities.
- `Manager`: tenant administrator. It can administer its own restaurant but cannot discover or address another restaurant's records.
- Operational staff: waiter, bar, kitchen, content, and other roles are memberships inside one restaurant. A user may have memberships in more than one restaurant if needed later.
- Authorization and shift state remain separate. A manager's admin capabilities do not disappear off shift. Going on shift only activates operational participation and alerts for selected work areas.

## Tenant resolution

Make the restaurant explicit in authenticated routes, for example:

```text
/api/restaurants/{restaurant_slug}/...
/ws/restaurants/{restaurant_slug}/staff/
```

For every request or WebSocket connection:

1. Authenticate the user.
2. Resolve the restaurant from the route.
3. Require an active membership for that restaurant, unless the user is the platform owner.
4. Scope every queryset and every object lookup to that restaurant.

Never trust a client-provided restaurant ID by itself. A valid ID without a membership check is an insecure direct-object-reference vulnerability.

Only the platform owner needs a restaurant switcher. Normal restaurant employees should enter their restaurant directly; if a user later belongs to multiple restaurants, show only those memberships.

## Data model changes

Introduce `Restaurant` (or rename the existing venue concept consistently) and attach it to all tenant-owned models, including:

- employees/memberships and staff preferences
- tables, menu categories, menu items, and venue settings
- orders, order items/events, calls, and tasks
- chat messages/read marks and checklist data
- coupons, campaigns, wallets, and social content
- push subscriptions where the subscription participates in restaurant alerts
- reminder/job state and any stored reports

Global uniqueness must become restaurant-local where appropriate. Examples:

```python
UniqueConstraint(fields=["restaurant", "number"], name="unique_table_per_restaurant")
UniqueConstraint(fields=["restaurant", "key"], name="unique_menu_category_per_restaurant")
UniqueConstraint(fields=["restaurant", "slug"], name="unique_campaign_per_restaurant")
```

Django supports multi-column `UniqueConstraint`s, which makes names and numbers reusable in different restaurants while preventing duplicates inside one restaurant. Add indexes beginning with `restaurant_id` for common list/filter paths. [Django constraints](https://docs.djangoproject.com/en/5.2/ref/models/constraints/)

Foreign-key validation must also prevent cross-restaurant relationships. For example, an order in Restaurant A cannot reference a table, menu item, employee, or coupon from Restaurant B. Query filtering alone is not enough for write validation.

## Application boundaries that must be scoped

- REST list, detail, create, update, and delete querysets
- serializer relation querysets and write validation
- staff bootstrap payloads and history/search endpoints
- guest menu, calls, wallets, and coupon redemption
- dashboard/admin views and exports
- WebSocket authentication, group names, and emitted events
- push-notification recipient selection
- scheduled jobs, reminders, cache keys, and idempotency/job keys
- uploads/media paths, seeds, fixtures, and destructive maintenance commands

The current global Channels group should become restaurant-qualified, such as `restaurant.{id}.staff`, with narrower capability or employee groups only when needed. Channels groups are designed for broadcast membership, and group names can safely encode this boundary. [Channels groups](https://channels.readthedocs.io/en/stable/topics/channel_layers.html#groups)

The current in-memory channel layer is appropriate for local development but cannot carry messages between multiple application processes. Use the official Redis channel layer before running multiple web instances. [Channels channel layers](https://channels.readthedocs.io/en/stable/topics/channel_layers.html)

## Why not one database or schema per restaurant

- Database per restaurant adds connection, migration, backup, monitoring, and provisioning work for every venue.
- Django does not support foreign-key or many-to-many relations across databases, which complicates platform-wide ownership and reporting. [Django multiple databases](https://docs.djangoproject.com/en/5.2/topics/db/multi-db/#limitations-of-multiple-databases)
- Schema per restaurant also multiplies migration and operational complexity and usually needs tenant-specific tooling.
- These approaches can become appropriate for contractual isolation, regional data residency, or very large tenants, but those requirements do not exist yet.

PostgreSQL Row-Level Security can later provide defense in depth, but it should not replace correct Django scoping. It also needs careful connection-context handling, and database/table owners normally bypass policies unless forced. [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

## Safe rollout

1. Add `Restaurant`, create the initial `sissy-bar` row, and add nullable restaurant foreign keys without changing behavior.
2. Backfill every existing tenant-owned row to `sissy-bar`; report and repair inconsistent relationships.
3. Add restaurant-aware memberships and derive existing roles/capabilities into them.
4. Centralize request tenant resolution and scope every API, serializer relation, dashboard, guest route, WebSocket, push, job, cache, and command.
5. Add composite constraints/indexes and cross-restaurant write validation; then make restaurant foreign keys non-null.
6. Update Flutter to carry the active restaurant slug in API/WebSocket routes. Add a restaurant switcher only for the platform owner.
7. Run isolation tests with at least two restaurants for every read/write/realtime path.
8. Only after those tests pass, expose restaurant creation and onboard the second restaurant.

Use additive migrations and a data backfill; do not delete or recreate the current database.

## Required acceptance tests

- A manager in Restaurant A cannot list, retrieve, guess the ID of, update, or subscribe to Restaurant B data.
- Relation writes reject cross-restaurant table/item/employee/coupon IDs.
- Guest URLs resolve only the requested restaurant's menu, calls, and branding.
- Restaurant A events never reach Restaurant B WebSocket or push subscribers.
- Background jobs process and record state independently per restaurant.
- Identical table numbers, category keys, and campaign slugs work in different restaurants.
- The platform owner can switch restaurants and receives an auditable restaurant context for every action.

## Current-code risks found

- Most core models have no restaurant relation and many querysets are global.
- Staff bootstrap currently returns global tables, menu, orders, and history.
- serializer relation querysets are global.
- WebSocket broadcasts use one global `staff` group.
- chat channels, jobs, seeds, and reload commands are global.
- `VenueSettings` already accepts a slug, but most callers use the default singleton and other models are not linked to it.
- DRF page-number pagination already exists; it limits response size but does not isolate restaurant data.

The migration must therefore establish tenant scoping end-to-end before adding a restaurant selector.
