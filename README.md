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
| M3 | Production resources — machines, configurable parameters, cost rates, time engine | ⬜ Planned |
| M4 | Materials & inventory — materials, stock movement ledger | ⬜ Planned |
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
