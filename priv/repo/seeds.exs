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
