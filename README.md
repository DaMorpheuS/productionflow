# Productionflow

**An order-management system for manufacturing & production companies.**

Productionflow is built to be *open about the production processes it handles*.
Instead of hard-coding one industry's workflow, you define your own machines and
work centres with configurable parameters (setup time, running speed, drying
time, …) from which the system calculates how long a job takes. Prices are built
up from real costs — machine time, operator/labour, materials and energy — with
price lists able to override the calculated price. The first concrete use case is
a print shop, but nothing in the core is print-specific.

The application is built **step by step in clean, independently shippable
milestones**. Each milestone is fully tested and ends in its own commit.

---

## Tech stack

- **Elixir** + **Phoenix 1.8** (LiveView 1.2)
- **PostgreSQL** via Ecto
- **Tailwind CSS** + **esbuild** (no Node build step required)
- **Swoosh** for transactional email, **gettext** for translatable UI
- Server: **Bandit**

---

## Status & roadmap

| # | Milestone | Status |
|---|-----------|--------|
| M1 | Core foundation — auth, roles & permissions, admin UI, app shell | ✅ Done |
| M2 | Relations (CRM-light) — relations, contacts, addresses, notes | ✅ Done |
| M3 | Production resources — machines, time engine, internal-cost calculator | ✅ Done |
| M4 | Materials & inventory — materials, categories, stock movement ledger | ✅ Done |
| M5a | Catalog — product templates (production route + bill of materials) + cost/time preview | ✅ Done |
| M5b | Pricing — customer price (margin) + price lists + quote view | ✅ Done |
| M6 | Orders — orders, lines, per-line production routes, lifecycle, stock consumption | ✅ Done |
| M7 | Quotes — a quote is an order in a pre-acceptance stage; send by email, customer accepts/declines, decline/revise/archive | ✅ Done |
| M8 | Planning — scheduling board: order route steps onto machines over time, per-machine queues, drag-drop, due dates | ✅ Done |
| M9 | Hardening & dashboard — overview dashboard, global search, richer demo data | ✅ Done |

---

## What's built so far

### M1 — Core foundation

- **Authentication** (Phoenix scope-based, magic-link + password login).
- **Configurable permission system**: roles are data; the set of possible
  permissions is a code-defined catalog. A role grants any subset, validated on
  save. `x.manage` automatically implies `x.view`.
- **Enforcement at three layers**: a route plug, a LiveView `on_mount` hook, and
  permission-gated navigation/buttons.
- **Admin UI** for managing roles (permission checkbox grid) and users (invite by
  email, assign role, activate/deactivate). Public registration is disabled —
  onboarding is admin-driven.
- **App shell**: sidebar layout with navigation that adapts to your permissions,
  an authenticated dashboard, and a seeded administrator account.

### M2 — Relations (CRM-light)

- **Relations** (companies) that can be customer, supplier and/or prospect, with
  optional unique code, email, phone, website, VAT number, IBAN and free-text
  remarks. Archived rather than deleted, so history stays intact.
- **Multiple typed addresses** per relation (invoice / delivery / visiting) with a
  single-default rule.
- **Contacts** with their own details, optionally placed at one of the relation's
  locations — and the contact form can create a new location on the fly.
- **Notes / activity timeline** per relation, attributed to the author and shown
  newest-first.
- Searchable, filterable relation list (by type, with an archived toggle), all
  gated by `crm.view` / `crm.manage` permissions.

### M3 — Production resources

- **Machines** with a generic time model that works for any kind of production:
  time = setup + (quantity ÷ units-per-hour), against each machine's own output
  unit (pieces, metres, m², kg, …).
- **Time modifiers** per machine — named additions (a percentage or a fixed
  number of minutes, e.g. "complex shape +20%") you switch on for a job when it
  needs more time.
- **Internal-cost engine**: the machine's cost per hour is derived from its
  write-off (purchase − residual ÷ lifetime) plus yearly maintenance over its
  productive hours; labour is the sum of the assigned operators' hourly cost
  (operators are users, each with an hourly cost); energy is power draw × the
  organization energy price.
- **Live cost helper**: as you fill in a machine's cost basis, the form shows its
  internal cost per hour update in real time.
- **Estimate widget**: on a machine you enter a quantity, tick any modifiers, and
  immediately see the duration and the machine / labour / energy / total internal
  cost — all gated by `production.view` / `production.manage`.

### M4 — Materials & inventory

- **Materials** with unit, cost & sales price, optional SKU, an optional
  **supplier** (linked to a relation) and the supplier's own article code, and a
  **category** for organization. Searchable and filterable by category, low
  stock, and archived state.
- **Stock as a movement ledger**: stock is never edited directly. Every
  **purchase**, **consumption** or **adjustment** is a signed entry, and the
  material's current stock is kept in sync transactionally — so the running
  total always equals the sum of its movements.
- **Smart bookings**: receiving a purchase with a unit cost updates the
  material's cost price (last-purchase-price); adjustments support both
  "set to counted amount" (stock-take) and a signed +/− delta; consumption may
  take stock negative (back-orders) with a clear warning badge.
- **Opening stock** can be entered when creating a material, and **low-stock**
  thresholds flag materials that need reordering.
- Three permission levels: `inventory.view` (see), `inventory.manage` (edit
  materials & categories), `inventory.book` (book stock movements).
- **Material types with custom fields** (modular): define material *types* (e.g.
  "Sheet paper", "Roll media"), each with its own custom fields — text, number
  (with a unit like mm or g/m²), yes/no, or a dropdown of choices, with optional
  required flag and default. A material picks a type and its form then shows
  those fields; values are validated and stored per material, so you can capture
  thickness, grammage, width, coating, etc. without code changes.

### M5a — Catalog (product templates)

- **Product templates** = a reusable recipe for something you make: a
  **production route** (ordered steps on machines) plus a **bill of materials**.
- **Route steps** each pick a machine and a **quantity factor** — how many
  machine units one product unit needs (e.g. 0.25 sheet per flyer for 4-up
  printing, or multiple passes). Optional per-machine time modifiers can be
  switched on per step.
- **Bill of materials** lines are fully flexible: a quantity per product unit
  (fractional, e.g. 0.25 sheet/item, or large, e.g. 5 ml ink/item) plus an
  optional **waste %**.
- **Cost & time preview**: enter a quantity on a product and instantly see the
  total production time and the internal cost broken down into machine, labour,
  energy and materials — plus the cost per unit. (Customer pricing with margin
  and price lists comes next, in M5b.)
- Gated by `catalog.view` / `catalog.manage`. Referenced machines and materials
  are protected from deletion so a recipe can't be silently broken.

### M5b — Pricing

- **Default margin** turns internal cost into a sales price as a **markup on
  cost** (`price = cost × (1 + margin%)`). A global default lives in pricing
  settings; any product template can override it with its own margin.
- **Price lists are managed from the product**: open a product and add prices
  there, choosing **General** or a specific **customer** — the product is
  already implied. There are no separate price-list screens; behind the scenes
  each scope is an automatic bucket (one general, one per customer).
- Prices are **graduated, per-unit tiers** (per piece, per m² — per whatever the
  product's output unit is): the highest tier whose *from quantity* is reached
  sets the price, so larger orders can get a better unit price. A tier is either
  a **fixed price** or a **% discount** off the calculated price.
- **Customer-specific pricing**: when pricing for a customer, a matching
  customer-bound tier beats the general one; otherwise general tiers apply.
- **Quote view**: pick a product, a quantity and (optionally) a customer to see
  the cost build-up, the default-margin price, the resolved price-list price and
  the resulting **margin in € and %** — including a clear warning when a chosen
  price sits **below internal cost** (a deliberate commercial call the tool
  surfaces rather than hides).
- Gated by `pricing.view` / `pricing.manage`.

### M6 — Orders

- An **order** belongs to a customer and is made of one or more **lines**. A line
  is either created **from a product template** — **snapshotting** its customer
  price, internal cost and margin (via the pricing engine) and **copying** the
  production route + bill of materials — or built **ad-hoc** (a one-off item with
  its own machines + materials, optionally a manual price); its cost is computed
  from those as you build it. Either way the order is a frozen record, unaffected
  by later price/machine/material changes.
- **Configurable numbering** (Order numbering settings): a per-year sequence
  (`ORD-2026-0001`, the default) or a continuous one, with a custom prefix.
- **Lifecycle** `draft → confirmed → in_production → completed` (plus
  `cancelled`), with illegal jumps rejected. Each route step has its own
  `pending → in_progress → done` status; a line's status and the order's
  progress roll up from the steps.
- **Completion consumes stock**: when every step is done you can complete the
  order, which books a consumption movement for each line's materials (stock may
  go negative — a material can be specially purchased for the order). Orders are
  cancelled, never deleted.
- **Line dependencies**: a line can depend on others (e.g. an assembly needs its
  sub-items first); a blocked line can't start until its dependencies are done.
- **Editable until production**: an order (header, lines, deliveries) stays
  editable while `draft` *and* `confirmed`; it locks — freezing the snapshots —
  once it goes into production.
- **Delivery addresses**: an order can be delivered to one or more addresses,
  chosen from the customer's saved addresses or typed one-off (optionally saved
  back onto the customer). Each line's quantity is **auto-split equally** across
  the delivery addresses (and re-divided when one is added or removed), with
  manual per-address overrides.
- Gated by `orders.view` / `orders.manage`.

### M7 — Quotes

- A **quote is the same document as an order**, in an earlier stage. Lifecycle:
  `draft → sent → accepted → in_production → completed`, with `declined` and
  `cancelled`. **Accepting a quote turns it into an order** (and assigns its
  order number). The **Quotes** and **Orders** lists are two filtered views of
  the same documents.
- **Numbering** is configurable like orders: a **quote number**
  (`QUO-2026-0001`, default per-year) at creation, an **order number**
  (`ORD-…`) on acceptance.
- **Declining** records a reason (Price / Technically wrong / Other) with notes;
  a declined quote can be **revised** back to a draft and re-sent, or
  **archived** (archiving always needs a reason — you can archive a quote
  yourself too). Archived documents drop out of the default lists.
- **Email the quote** to the customer: "Send to customer" emails a secure
  **public link** (no login) where they review the quote and **accept** (it
  becomes an order) or **decline** (with a reason). The link is a hashed,
  expiring token and is consumed once a decision is made.

### M8 — Planning

- A **scheduling board** that places each order's **route steps** onto the
  machines that run them, over time. Columns are machines plus an
  **Unscheduled** backlog; cards are route steps from **accepted** and
  **in-production** orders.
- **Drag a card** from the backlog onto a machine to schedule it, reorder within
  a machine to sequence the queue, or drag it back to unschedule. A step only
  fits **its own** machine. Each machine packs its queue **back-to-back** across
  its **working hours** (a daily window + working weekdays, configured per
  machine), rolling onto the next working day when a step overflows.
- Cards show the computed **start time** and flag work planned to finish **after
  its due date** (`late`) or scheduled **out of route order** (`order`). From an
  in-production order's card you can **Start** / mark **Done**, which advances the
  underlying route step; done steps drop off the board.
- The board packs forward from a configurable **Schedule from** date (never
  earlier than today). Viewing needs `planning.view`; dragging and settings need
  `planning.manage`.

### M9 — Hardening: dashboard & search

- The home page is now an **overview dashboard**. **Needs attention** surfaces
  overdue orders, low/negative stock, and unscheduled or late production steps;
  **KPIs** show open quotes, active orders, low-stock count, stock value,
  machines and customers; **Recent activity** lists the latest documents. Every
  widget is permission-gated and links through to the relevant list, so each role
  sees only what it may.
- A **global search** box in the header searches across **orders, relations,
  materials and products** at once, grouped by type and gated per permission.
- **Demo seeds** were enriched — orders spread across the status lifecycle
  (including an overdue one), extra relations of each type, and some low-stock
  materials — so the dashboard and lists are populated out of the box.

---

## Getting started

### Prerequisites

- Elixir & Erlang/OTP (see `.tool-versions` / `mix.exs` for versions)
- PostgreSQL running locally (default config expects user `postgres` / password
  `postgres` on `localhost`)

### Setup

```bash
mix setup          # install deps, create & migrate the database, build assets
mix run priv/repo/seeds.exs   # create the Administrator role + admin user
mix phx.server     # start the app on http://localhost:4000
```

### First login

There is no public sign-up. The seed creates an administrator
(`admin@productionflow.local`, override with the `ADMIN_EMAIL` env var). To log
in during development:

1. Visit `http://localhost:4000/users/log-in` and enter the admin email.
2. Open the local mailbox at `http://localhost:4000/dev/mailbox` and follow the
   magic-link to sign in (you can set a password afterwards in Settings).

From there you can create roles and invite other users under **Administration**.

---

## Running the tests

```bash
mix test          # full suite
mix precommit     # compile (warnings as errors) + format check + tests
```

`mix precommit` is the gate every milestone must pass before it is committed.

---

## Project layout

```
lib/
  productionflow/            # business logic, one module per context
    accounts/                #   users, roles, permissions, scope (M1)
    crm/                     #   relations, addresses, contacts, notes (M2)
  productionflow_web/        # web layer
    live/                    #   LiveViews (admin, crm, dashboard)
    components/              #   layouts & shared UI components
priv/repo/migrations/        # database migrations
test/                        # context tests + LiveView tests
```

Contexts only call each other through their public functions; downstream data
(prices, parameters) is snapshotted into orders rather than joined live.

---

*Productionflow is under active, milestone-by-milestone development. This README is
updated with every milestone — see the status table above for the current state.*
