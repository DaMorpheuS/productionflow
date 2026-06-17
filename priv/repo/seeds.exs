# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Productionflow.Repo.insert!(%Productionflow.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias Productionflow.Repo
alias Productionflow.Accounts
alias Productionflow.Accounts.{Role, User, Permissions}
alias Productionflow.Inventory
alias Productionflow.Inventory.{Category, Material, MaterialType, FieldDefinition}
alias Productionflow.Production
alias Productionflow.Production.Machine
alias Productionflow.Catalog
alias Productionflow.Catalog.ProductTemplate
alias Productionflow.Pricing
alias Productionflow.Pricing.PriceListItem
alias Productionflow.CRM
alias Productionflow.Orders
alias Productionflow.Planning

# Idempotent: an Administrator role holding every permission, and an admin user
# assigned to it. Re-running keeps both in sync.

admin_role =
  case Repo.get_by(Role, name: "Administrator") do
    nil ->
      {:ok, role} =
        Accounts.create_role(%{
          name: "Administrator",
          description: "Full access to every part of the system.",
          permissions: Permissions.all()
        })

      role

    role ->
      {:ok, role} = Accounts.update_role(role, %{permissions: Permissions.all()})
      role
  end

admin_email = System.get_env("ADMIN_EMAIL", "admin@productionflow.local")

case Repo.get_by(User, email: admin_email) do
  nil ->
    {:ok, _user} =
      Accounts.create_user(%{
        email: admin_email,
        name: "Administrator",
        active: true,
        role_id: admin_role.id
      })

    IO.puts("""
    Created admin user #{admin_email}.
    Log in via the magic link: visit /users/log-in, enter the email, then open
    /dev/mailbox to follow the login link and set a password.
    """)

  user ->
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role_id: admin_role.id])
    IO.puts("Admin user #{admin_email} already exists; ensured Administrator role.")
end

# Demo inventory for a printing company, using material types with custom
# fields. Re-runnable: types/categories are matched by name; the demo materials
# are fully replaced on each run (deleted by SKU, then recreated with their
# type + attributes) so they always reflect the latest setup.

ensure_category = fn name ->
  case Repo.get_by(Category, name: name) do
    nil ->
      {:ok, category} = Inventory.create_category(%{name: name})
      category

    category ->
      category
  end
end

ensure_type = fn name ->
  case Repo.get_by(MaterialType, name: name) do
    nil ->
      {:ok, type} = Inventory.create_material_type(%{name: name})
      type

    type ->
      type
  end
end

ensure_field = fn type, attrs ->
  case Repo.get_by(FieldDefinition, material_type_id: type.id, key: attrs.key) do
    nil -> {:ok, _} = Inventory.create_field_definition(type, attrs)
    field -> {:ok, _} = Inventory.update_field_definition(field, attrs)
  end
end

# Material types and their custom field definitions.
types = [
  {"Sheet paper",
   [
     %{key: "grammage", label: "Grammage", field_type: :number, unit: "g/m²", position: 1},
     %{key: "thickness", label: "Thickness", field_type: :number, unit: "µm", position: 2},
     %{
       key: "coating",
       label: "Coating",
       field_type: :select,
       options: ["uncoated", "gloss", "matte", "silk"],
       position: 3
     }
   ]},
  {"Roll media",
   [
     %{key: "width", label: "Roll width", field_type: :number, unit: "mm", position: 1},
     %{
       key: "finish",
       label: "Finish",
       field_type: :select,
       options: ["gloss", "matte"],
       position: 2
     },
     %{key: "adhesive", label: "Self-adhesive", field_type: :boolean, position: 3}
   ]},
  {"Rigid board",
   [
     %{key: "thickness", label: "Thickness", field_type: :number, unit: "mm", position: 1}
   ]}
]

type_by_name =
  Map.new(types, fn {name, fields} ->
    type = ensure_type.(name)
    Enum.each(fields, &ensure_field.(type, &1))
    {name, type}
  end)

# Demo materials. Optional :type (a type name) + :attributes (string-keyed map
# validated against that type's fields).
materials = [
  %{
    sku: "PAP-90-OFF",
    name: "Offset paper 90g",
    category: "Paper",
    unit: "sheet",
    cost_price: "0.012",
    sales_price: "0.04",
    minimum_stock: "2000",
    opening_stock: "12000",
    type: "Sheet paper",
    attributes: %{"grammage" => "90", "thickness" => "100", "coating" => "uncoated"}
  },
  %{
    sku: "PAP-120-SILK",
    name: "Silk paper 120g",
    category: "Paper",
    unit: "sheet",
    cost_price: "0.02",
    sales_price: "0.07",
    minimum_stock: "1000",
    opening_stock: "6000",
    type: "Sheet paper",
    attributes: %{"grammage" => "120", "thickness" => "115", "coating" => "silk"}
  },
  %{
    sku: "PAP-300-GLOSS",
    name: "Gloss card 300g",
    category: "Paper",
    unit: "sheet",
    cost_price: "0.05",
    sales_price: "0.15",
    minimum_stock: "500",
    opening_stock: "2500",
    type: "Sheet paper",
    attributes: %{"grammage" => "300", "thickness" => "330", "coating" => "gloss"}
  },
  %{
    sku: "PAP-SRA3-135",
    name: "Coated SRA3 135g",
    category: "Paper",
    unit: "sheet",
    cost_price: "0.06",
    sales_price: "0.16",
    minimum_stock: "500",
    opening_stock: "3000",
    type: "Sheet paper",
    attributes: %{"grammage" => "135", "thickness" => "140", "coating" => "matte"}
  },
  %{
    sku: "ROLL-PVC-510",
    name: "PVC banner 510g",
    category: "Substrates",
    unit: "m²",
    cost_price: "3.50",
    sales_price: "12.00",
    minimum_stock: "20",
    opening_stock: "120",
    type: "Roll media",
    attributes: %{"width" => "1370", "finish" => "matte", "adhesive" => "false"}
  },
  %{
    sku: "ROLL-SAV-MATTE",
    name: "Self-adhesive vinyl (matte)",
    category: "Substrates",
    unit: "m²",
    cost_price: "4.20",
    sales_price: "14.00",
    minimum_stock: "15",
    opening_stock: "80",
    type: "Roll media",
    attributes: %{"width" => "1370", "finish" => "matte", "adhesive" => "true"}
  },
  %{
    sku: "ROLL-SAV-GLOSS",
    name: "Self-adhesive vinyl (gloss)",
    category: "Substrates",
    unit: "m²",
    cost_price: "4.40",
    sales_price: "14.50",
    minimum_stock: "15",
    opening_stock: "60",
    type: "Roll media",
    attributes: %{"width" => "1600", "finish" => "gloss", "adhesive" => "true"}
  },
  %{
    sku: "BOARD-FOAM-5",
    name: "Foamboard 5mm",
    category: "Substrates",
    unit: "m²",
    cost_price: "6.00",
    sales_price: "18.00",
    minimum_stock: "10",
    opening_stock: "40",
    type: "Rigid board",
    attributes: %{"thickness" => "5"}
  },
  %{
    sku: "BOARD-DIBOND-3",
    name: "Dibond 3mm",
    category: "Substrates",
    unit: "m²",
    cost_price: "14.00",
    sales_price: "38.00",
    minimum_stock: "8",
    opening_stock: "30",
    type: "Rigid board",
    attributes: %{"thickness" => "3"}
  },
  %{
    sku: "INK-ECO-C",
    name: "Eco-solvent ink — Cyan",
    category: "Ink & Toner",
    unit: "L",
    cost_price: "45.00",
    minimum_stock: "2",
    opening_stock: "8"
  },
  %{
    sku: "INK-ECO-M",
    name: "Eco-solvent ink — Magenta",
    category: "Ink & Toner",
    unit: "L",
    cost_price: "45.00",
    minimum_stock: "2",
    opening_stock: "8"
  },
  %{
    sku: "INK-ECO-Y",
    name: "Eco-solvent ink — Yellow",
    category: "Ink & Toner",
    unit: "L",
    cost_price: "45.00",
    minimum_stock: "2",
    opening_stock: "8"
  },
  %{
    sku: "INK-ECO-K",
    name: "Eco-solvent ink — Black",
    category: "Ink & Toner",
    unit: "L",
    cost_price: "45.00",
    minimum_stock: "2",
    opening_stock: "10"
  },
  %{
    sku: "TON-K",
    name: "Toner cartridge — Black",
    category: "Ink & Toner",
    unit: "cartridge",
    cost_price: "62.00",
    minimum_stock: "2",
    opening_stock: "6"
  },
  %{
    sku: "FIN-LAM-G",
    name: "Lamination film — gloss 30µm",
    category: "Finishing",
    unit: "m",
    cost_price: "0.15",
    sales_price: "0.45",
    minimum_stock: "100",
    opening_stock: "500"
  },
  %{
    sku: "FIN-LAM-M",
    name: "Lamination film — matte 30µm",
    category: "Finishing",
    unit: "m",
    cost_price: "0.17",
    sales_price: "0.50",
    minimum_stock: "100",
    opening_stock: "400"
  },
  %{
    sku: "FIN-WIREO",
    name: "Wire-o binding spine 3:1",
    category: "Finishing",
    unit: "pieces",
    cost_price: "0.20",
    sales_price: "0.70",
    minimum_stock: "200",
    opening_stock: "1000"
  },
  %{
    sku: "CON-STAPLE",
    name: "Saddle-stitch staples",
    category: "Consumables",
    unit: "pieces",
    cost_price: "0.004",
    minimum_stock: "5000",
    opening_stock: "20000"
  },
  %{
    sku: "CON-GROM",
    name: "Banner eyelets / grommets",
    category: "Consumables",
    unit: "pieces",
    cost_price: "0.08",
    sales_price: "0.30",
    minimum_stock: "200",
    opening_stock: "1000"
  },
  %{
    sku: "CON-TAPE",
    name: "Double-sided mounting tape",
    category: "Consumables",
    unit: "roll",
    cost_price: "4.00",
    minimum_stock: "5",
    opening_stock: "20"
  }
]

# Remove the demo product template first (cascades its bill of materials) so the
# materials it references can be replaced below despite the :restrict FK. Its
# price tiers AND any demo orders' lines reference it via :restrict FKs, so clear
# those first (deleting the orders cascades their lines/steps/materials).
flyer_order_ids =
  Repo.all(
    from(o in Productionflow.Orders.Order,
      join: l in Productionflow.Orders.OrderLine,
      on: l.order_id == o.id,
      join: t in ProductTemplate,
      on: t.id == l.product_template_id,
      where: t.sku == "PRD-FLY-A5",
      distinct: true,
      select: o.id
    )
  )

Repo.delete_all(from(o in Productionflow.Orders.Order, where: o.id in ^flyer_order_ids))

Repo.delete_all(
  from(i in PriceListItem,
    join: t in ProductTemplate,
    on: t.id == i.product_template_id,
    where: t.sku == "PRD-FLY-A5"
  )
)

Repo.delete_all(from(t in ProductTemplate, where: t.sku == "PRD-FLY-A5"))

# Remove any previously seeded demo materials (old and current SKUs), cascading
# their stock movements, then recreate from the list above.
old_skus = ~w(PAP-90-A4 PAP-120-A4 PAP-300-A4 SUB-VINYL-510 SUB-SAV SUB-FOAM-5 SUB-DIBOND-3)
managed_skus = Enum.map(materials, & &1.sku) ++ old_skus
Repo.delete_all(from(m in Material, where: m.sku in ^managed_skus))

Enum.each(materials, fn material ->
  category = ensure_category.(material.category)

  attrs =
    material
    |> Map.drop([:category, :type, :attributes])
    |> Map.put(:category_id, category.id)

  attrs =
    case material[:type] do
      nil ->
        attrs

      type_name ->
        Map.merge(attrs, %{
          material_type_id: Map.fetch!(type_by_name, type_name).id,
          attributes: material.attributes
        })
    end

  {:ok, _} = Inventory.create_material(attrs)
end)

typed = Enum.count(materials, & &1[:type])

IO.puts(
  "Inventory seed: replaced demo materials — #{length(materials)} created " <>
    "(#{typed} with a material type) across #{map_size(type_by_name)} types."
)

# Demo production machine + a product template (route + bill of materials), so
# the catalog cost/time preview has real data. Idempotent: machine by name, the
# product template deleted-and-recreated by SKU.

# Organization energy tariff so the energy cost line is non-zero.
{:ok, _} = Production.update_settings(%{energy_price_per_kwh: "0.30"})

press =
  case Repo.get_by(Machine, name: "Digital press") do
    nil ->
      {:ok, machine} =
        Production.create_machine(%{
          name: "Digital press",
          output_unit: "sheet",
          units_per_hour: "4000",
          setup_minutes: "10",
          power_kw: "2.5",
          purchase_price: "80000",
          residual_value: "5000",
          lifetime_years: "7",
          yearly_maintenance_cost: "6000",
          productive_hours_per_year: "1500",
          working_day_start: "06:00",
          working_day_end: "22:00"
        })

      machine

    machine ->
      machine
  end

flyer_sku = "PRD-FLY-A5"
Repo.delete_all(from(t in ProductTemplate, where: t.sku == ^flyer_sku))

{:ok, flyer} =
  Catalog.create_product_template(%{
    name: "A5 flyer 4/4",
    sku: flyer_sku,
    output_unit: "flyer",
    description: "A5 full-colour flyer, double-sided, printed 4-up on the digital press."
  })

# 4 flyers per sheet → 0.25 sheet per flyer.
{:ok, _} =
  Catalog.add_route_step(flyer, %{"machine_id" => press.id, "quantity_per_unit" => "0.25"})

for {sku, qty_per_unit, waste} <- [{"PAP-90-OFF", "0.25", "3"}, {"INK-ECO-K", "0.002", "0"}] do
  if material = Repo.get_by(Material, sku: sku) do
    {:ok, _} =
      Catalog.add_template_material(flyer, %{
        "material_id" => material.id,
        "quantity_per_unit" => qty_per_unit,
        "waste_pct" => waste
      })
  end
end

IO.puts("Catalog seed: ensured demo machine \"#{press.name}\" and product \"#{flyer.name}\".")

# Demo pricing: a default margin plus general volume tiers for the flyer, so the
# quote view resolves a graduated price. The flyer's old tiers were cleared above
# with its template, so we just add the current general tiers here.
{:ok, _} = Pricing.update_settings(%{default_margin_pct: "35"})

for {min_qty, price} <- [{"1", "0.18"}, {"1000", "0.12"}, {"5000", "0.08"}] do
  {:ok, _} =
    Pricing.add_template_price_tier(flyer, %{
      "scope_relation_id" => "",
      "min_quantity" => min_qty,
      "kind" => "fixed_price",
      "unit_price" => price
    })
end

IO.puts("Pricing seed: set default margin and ensured general volume tiers for the flyer.")

# Demo customer + a quote (with one flyer line) that is accepted into an order, so
# both the quotes and orders areas have real data. Idempotent: the customer is
# matched by name, and the document is only created when that customer has none.
demo_customer =
  case Repo.get_by(CRM.Relation, name: "Demo Print Customer") do
    nil ->
      {:ok, c} = CRM.create_relation(%{name: "Demo Print Customer", is_customer: true})
      c

    c ->
      c
  end

unless Repo.exists?(
         from(o in Productionflow.Orders.Order, where: o.relation_id == ^demo_customer.id)
       ) do
  {:ok, order} =
    Orders.create_order(%{"relation_id" => demo_customer.id, "reference" => "DEMO-SEED"})

  {:ok, _} = Orders.add_line_from_template(order, flyer.id, "1000")

  {:ok, _} =
    Orders.add_delivery(order, %{
      "street" => "Keizersgracht 123",
      "postal_code" => "1015 CJ",
      "city" => "Amsterdam",
      "country" => "NL",
      "save_to_customer" => "true"
    })

  {:ok, order} = Orders.accept_quote(order)

  IO.puts(
    "Orders seed: created quote #{order.quote_number}, accepted as order #{order.number} " <>
      "for #{demo_customer.name}."
  )

  # Place the accepted order's print step onto the board so Planning has data.
  step =
    order.id
    |> Orders.get_order!()
    |> Map.fetch!(:lines)
    |> List.first()
    |> Map.fetch!(:route_steps)
    |> List.first()

  {:ok, _} = Planning.schedule_step(step, step.machine_id)
  IO.puts("Planning seed: scheduled the demo order's print step on #{step.machine_name}.")
end

# Richer demo data so the dashboard and lists look populated: a couple of
# low-stock materials, extra relations across types, and flyer orders spread
# over the status lifecycle (incl. an overdue one). All idempotent.

for {sku, name, unit, cost, min, opening} <- [
      {"DEMO-LOW-FILM", "Lamination film (gloss)", "m", "1.20", "500", "120"},
      {"DEMO-LOW-GLUE", "Binding glue", "kg", "8.50", "25", "4"}
    ] do
  unless Repo.get_by(Material, sku: sku) do
    {:ok, _} =
      Inventory.create_material(%{
        name: name,
        unit: unit,
        sku: sku,
        cost_price: cost,
        minimum_stock: min,
        opening_stock: opening
      })
  end
end

IO.puts("Inventory seed: ensured demo low-stock materials.")

for attrs <- [
      %{name: "Studio Noord", is_customer: true},
      %{name: "Bakkerij Janssen", is_customer: true},
      %{name: "Inkt & Papier BV", is_supplier: true},
      %{name: "Festival Collectief", is_prospect: true}
    ] do
  unless Repo.get_by(CRM.Relation, name: attrs.name) do
    {:ok, _} = CRM.create_relation(attrs)
  end
end

studio = Repo.get_by!(CRM.Relation, name: "Studio Noord")
bakkerij = Repo.get_by!(CRM.Relation, name: "Bakkerij Janssen")
admin_user = Repo.get_by!(User, email: admin_email)

first_route_step = fn order ->
  order.id
  |> Orders.get_order!()
  |> Map.fetch!(:lines)
  |> List.first()
  |> Map.fetch!(:route_steps)
  |> List.first()
end

# Builds a flyer order for `customer` and drives it to `target` status, scheduling
# its step where that makes sense. Statuses follow draft → sent → accepted →
# in_production → completed.
seed_flyer_order = fn customer, reference, qty, target, due ->
  attrs = %{"relation_id" => customer.id, "reference" => reference}
  attrs = if due, do: Map.put(attrs, "due_date", Date.to_iso8601(due)), else: attrs

  {:ok, order} = Orders.create_order(attrs)
  {:ok, _} = Orders.add_line_from_template(order, flyer.id, qty)

  case target do
    :draft ->
      order

    :sent ->
      {:ok, sent} = Orders.transition_order(order, :sent)
      sent

    _ ->
      {:ok, _} = Orders.add_pickup(order)
      {:ok, accepted} = Orders.accept_quote(order)

      case target do
        :accepted ->
          accepted

        :in_production ->
          {:ok, in_prod} = Orders.transition_order(accepted, :in_production)
          step = first_route_step.(in_prod)
          {:ok, _} = Planning.schedule_step(step, step.machine_id)
          in_prod

        :completed ->
          {:ok, in_prod} = Orders.transition_order(accepted, :in_production)
          step = first_route_step.(in_prod)
          {:ok, _} = Orders.advance_step(step, :in_progress)
          {:ok, _} = Orders.advance_step(Orders.get_line_route_step!(step.id), :done)
          {:ok, done} = Orders.complete_order(Orders.get_order!(in_prod.id), admin_user)
          done
      end
  end
end

unless Repo.exists?(from(o in Productionflow.Orders.Order, where: o.relation_id == ^studio.id)) do
  seed_flyer_order.(studio, "WEB-001", "500", :draft, nil)
  seed_flyer_order.(studio, "EVENT-007", "2000", :completed, Date.add(Date.utc_today(), -3))
  IO.puts("Orders seed: created a draft quote + a completed order for #{studio.name}.")
end

unless Repo.exists?(from(o in Productionflow.Orders.Order, where: o.relation_id == ^bakkerij.id)) do
  seed_flyer_order.(bakkerij, "MENU-Q", "1500", :sent, Date.add(Date.utc_today(), 10))
  seed_flyer_order.(bakkerij, "RUSH", "3000", :in_production, Date.add(Date.utc_today(), -1))

  IO.puts(
    "Orders seed: created a sent quote + an overdue in-production order for #{bakkerij.name}."
  )
end
