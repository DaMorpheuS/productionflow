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
| M5 | Catalog & pricing — product templates (routes) + cost-based pricing engine | ⬜ Planned |
| M6 | Orders — orders, lines, per-line production routes, lifecycle, stock consumption | ⬜ Planned |
| M7 | Hardening & dashboard — overview, search, demo data | ⬜ Planned |

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
