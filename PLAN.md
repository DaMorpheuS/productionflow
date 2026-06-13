# Productionflow — Project Plan

## Context

Greenfield order-management system for manufacturing/production companies (first use case: a print company), built on a clean Phoenix 1.8.8 install (LiveView 1.2, PostgreSQL, Tailwind, Swoosh, gettext).

The system must be **open about what production processes it handles**: the user defines machines with configurable parameters from which the system calculates production time, and prices are built up from costs (machine + operator + material + power) with price lists able to override the calculated price. Built step by step in clean, independently shippable milestones.

### Agreed product decisions
- **Time model**: configurable parameters per machine (setup time, speed, etc.), parameter sets differ per process type.
- **Pricing**: default = cost build-up (machine cost + labor + materials + energy); price lists override per item; per-customer lists later.
- **Routing**: product templates carry a default route (sequence of steps on machines); orders copy & adjust it, or compose a one-off route. A template is a saved route.
- **Materials**: cost/sales prices AND stock levels from day one (movement ledger).
- **Users**: staff with configurable permissions (roles = data, permissions validated against a code-defined list). Customer portal much later — don't paint into a corner.
- **Relations**: CRM-light — customers/suppliers/prospects (flags, can be both), contacts, multiple typed addresses, notes/activity.
- **UI**: LiveView, English through gettext from day one (multi-language later).

## Milestone Roadmap

Dependency order: auth gates everything → relations are standalone and prove the patterns → machines/materials are inputs to pricing/templates → those are inputs to orders.

1. **M1 — Core foundation**: phx.gen.auth (scope-based), roles with configurable permission sets, enforcement (plug + on_mount + UI), admin UI for roles/users, sidebar app shell, seeds. *(detailed below — first thing to build)*
2. **M2 — Relations (CRM-light)**: `CRM` context — relations, contacts, addresses, notes. Pure CRUD LiveViews exercising permissions + UI patterns.
3. **M3 — Production resources**: `Production` context — process types + parameter definitions, machines + parameter values, hourly rates, power draw, labor rates, energy tariff; time-calculation engine with unit tests.
4. **M4 — Materials & inventory**: `Inventory` context — materials with prices/units, stock via movement ledger (purchase/consumption/adjustment), manual booking UI.
5. **M5 — Catalog & pricing**: `Catalog` (product templates = saved routes + bill of materials) and `Pricing` (cost build-up calculator with breakdown struct, price lists with quantity tiers, override resolution).
6. **M6 — Orders**: `Orders` context — orders, order lines (from template or one-off), per-line route steps with statuses, lifecycle with guarded transitions, price snapshots, stock consumption on completion. MVP finish line.
7. **M7 — Hardening/dashboard** (stretch): overview dashboard, search/filters, demo seed data. Later: planning/scheduling, quotes & invoicing, customer portal, documents, per-customer price lists.

## Context Architecture

| Context | Owns |
|---|---|
| `Accounts` | User, UserToken, Role, Scope; permission list in code (`Accounts.Permissions`) |
| `CRM` | Relation, Contact, Address, Note |
| `Production` | ProcessType, ParameterDefinition, Machine, MachineParameterValue, LaborRate, EnergyTariff, calculators |
| `Inventory` | Material, StockMovement (exposes `consume/3`, `receive/3`) |
| `Catalog` | ProductTemplate, TemplateRouteStep, TemplateMaterial (references other contexts by id) |
| `Pricing` | PriceList, PriceListItem, pure `Calculator`, non-persisted `Quote` struct |
| `Orders` | Order, OrderLine, OrderRouteStep, OrderLineMaterial (snapshots from Catalog/Pricing) |

Rules: contexts call each other's public functions only; orders snapshot prices/parameters rather than joining live data.

## Key Design Decisions

- **Parameters & time calc**: data-defined parameters + code-defined calculators. `Calculator` behaviour (`duration_minutes(params, quantity)`, `required_keys/0`) with implementations like `SetupPlusSpeed`, `SetupPlusSpeedPlusDrying`, `FixedDuration`. Process type picks the calculator; its parameter definitions drive machine forms. Value resolution: route-step override → machine value → definition default. (No string-formula interpreter — new calculation shapes are small tested modules.)
- **Permissions**: dotted strings (`"crm.manage"`, `"admin.roles"`…) stored as validated `{:array, :string}` on roles; canonical list in `Accounts.Permissions`. `Scope.can?(scope, perm)` via MapSet; enforced by a `require_permission` plug, an `on_mount {:require_permission, perm}` hook per live_session, and conditional UI. One role per user now; many-to-many later is a contained change.
- **Money**: `Decimal` on `numeric(12,4)` columns for rates/unit costs; round to 2 decimals only at final prices; shared `format_money/1` component. Single currency; no ex_money dependency.
- **Statuses**: `Ecto.Enum` on string columns; each schema owns a `@transitions` map + `transition_changeset/2` rejecting illegal jumps.
- **Price-list override**: always calculate the cost build-up first, then resolve best matching price-list item (relation-bound > general; highest `min_quantity ≤ qty`); override replaces unit price but keeps the cost breakdown (margin stays visible). Order lines persist price + breakdown + source.
- **Deletes**: `archived_at` on master data (excluded from pickers, fine in history); `on_delete: :restrict` FKs from orders; hard delete only when unreferenced; orders are cancelled, never deleted.

## Milestone 1 — Concrete Steps

1. **Baseline commit** of the stock install (`git add -A && git commit`).
2. `mix phx.gen.auth Accounts User users` (LiveView, Phoenix 1.8 scopes, magic-link + optional password) → `mix deps.get && mix ecto.migrate`, run generated tests.
3. **Migrations**: `roles` (name unique, description, `permissions {:array,:string} default []`); users get `role_id` (restrict), `name`, `active`. New `lib/productionflow/accounts/role.ex`; `belongs_to :role` on User.
4. **`lib/productionflow/accounts/permissions.ex`**: grouped `{key, label}` list covering `admin.*`, `crm.*`, `production.*`, `inventory.*`, `catalog.*`, `pricing.*`, `orders.*`; `all/0`, `groups/0`, `valid?/1`. Role changeset validates subset.
5. **Scope extension** (`lib/productionflow/accounts/scope.ex`): permissions MapSet built in `for_user/1` (preload role); `can?/2`, `admin?/1`.
6. **Enforcement** (`lib/productionflow_web/user_auth.ex`): `on_mount {:require_permission, perm}` clause + `require_permission` plug; `live_session :admin` in router.
7. **Admin LiveViews**: `live/admin/role_live/` (index + checkbox-grid form from `Permissions.groups/0`), `live/admin/user_live/` (list, invite via magic link, assign role, toggle active). Disable public registration — onboarding is admin-driven.
8. **App shell**: sidebar layout in `components/layouts.ex` + `root.html.heex`; nav gated by `Scope.can?`; all strings via gettext; `/` → placeholder dashboard behind auth.
9. **Seeds**: idempotent Administrator role (all permissions) + admin user.
10. **Tests**: permissions module, role CRUD, `Scope.can?/2`, on_mount deny/allow paths, admin LiveView tests (extend `register_and_log_in_user` with `role:` option in `test/support/conn_case.ex`).

## Verification

- `mix precommit` (compile --warnings-as-errors, format, full test suite) green after each milestone.
- M1 smoke test: seed, log in as admin, create a "Sales" role with only `crm.*`, log in as that user → `/admin/roles` blocked (redirect + flash), sidebar trimmed. Deny paths covered by tests, not just allow paths.
- Each milestone ends in its own commit(s); milestone is shippable/testable on its own.

## Critical files

`lib/productionflow_web/router.ex`, `lib/productionflow_web/user_auth.ex` (generated, then extended), `lib/productionflow/accounts/scope.ex`, `lib/productionflow/accounts/permissions.ex` (new), `lib/productionflow_web/components/layouts.ex`, `priv/repo/seeds.exs`.
