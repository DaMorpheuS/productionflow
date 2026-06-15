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
alias Productionflow.Inventory.{Category, Material}

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

# Demo inventory for a printing company. Idempotent: categories are matched by
# name and materials by SKU, so re-running the seeds adds nothing twice.

ensure_category = fn name ->
  case Repo.get_by(Category, name: name) do
    nil ->
      {:ok, category} = Inventory.create_category(%{name: name})
      category

    category ->
      category
  end
end

ensure_material = fn attrs ->
  case Repo.get_by(Material, sku: attrs.sku) do
    nil ->
      {:ok, _material} = Inventory.create_material(attrs)
      :created

    _material ->
      :exists
  end
end

# {category name, [material attrs (minus category_id)]}
inventory = [
  {"Paper",
   [
     %{
       sku: "PAP-90-A4",
       name: "Paper 90g A4",
       unit: "sheet",
       cost_price: "0.012",
       sales_price: "0.04",
       minimum_stock: "2000",
       opening_stock: "10000"
     },
     %{
       sku: "PAP-120-A4",
       name: "Paper 120g A4",
       unit: "sheet",
       cost_price: "0.02",
       sales_price: "0.06",
       minimum_stock: "1000",
       opening_stock: "5000"
     },
     %{
       sku: "PAP-300-A4",
       name: "Card 300g A4",
       unit: "sheet",
       cost_price: "0.05",
       sales_price: "0.14",
       minimum_stock: "500",
       opening_stock: "2000"
     },
     %{
       sku: "PAP-SRA3-135",
       name: "Coated SRA3 135g",
       unit: "sheet",
       cost_price: "0.06",
       sales_price: "0.16",
       minimum_stock: "500",
       opening_stock: "3000"
     }
   ]},
  {"Substrates",
   [
     %{
       sku: "SUB-VINYL-510",
       name: "PVC banner 510g",
       unit: "m²",
       cost_price: "3.50",
       sales_price: "12.00",
       minimum_stock: "20",
       opening_stock: "120"
     },
     %{
       sku: "SUB-SAV",
       name: "Self-adhesive vinyl (matte)",
       unit: "m²",
       cost_price: "4.20",
       sales_price: "14.00",
       minimum_stock: "15",
       opening_stock: "80"
     },
     %{
       sku: "SUB-FOAM-5",
       name: "Foamboard 5mm",
       unit: "m²",
       cost_price: "6.00",
       sales_price: "18.00",
       minimum_stock: "10",
       opening_stock: "40"
     },
     %{
       sku: "SUB-DIBOND-3",
       name: "Dibond 3mm",
       unit: "m²",
       cost_price: "14.00",
       sales_price: "38.00",
       minimum_stock: "8",
       opening_stock: "30"
     }
   ]},
  {"Ink & Toner",
   [
     %{
       sku: "INK-ECO-C",
       name: "Eco-solvent ink — Cyan",
       unit: "L",
       cost_price: "45.00",
       minimum_stock: "2",
       opening_stock: "8"
     },
     %{
       sku: "INK-ECO-M",
       name: "Eco-solvent ink — Magenta",
       unit: "L",
       cost_price: "45.00",
       minimum_stock: "2",
       opening_stock: "8"
     },
     %{
       sku: "INK-ECO-Y",
       name: "Eco-solvent ink — Yellow",
       unit: "L",
       cost_price: "45.00",
       minimum_stock: "2",
       opening_stock: "8"
     },
     %{
       sku: "INK-ECO-K",
       name: "Eco-solvent ink — Black",
       unit: "L",
       cost_price: "45.00",
       minimum_stock: "2",
       opening_stock: "10"
     },
     %{
       sku: "TON-K",
       name: "Toner cartridge — Black",
       unit: "cartridge",
       cost_price: "62.00",
       minimum_stock: "2",
       opening_stock: "6"
     }
   ]},
  {"Finishing",
   [
     %{
       sku: "FIN-LAM-G",
       name: "Lamination film — gloss 30µm",
       unit: "m",
       cost_price: "0.15",
       sales_price: "0.45",
       minimum_stock: "100",
       opening_stock: "500"
     },
     %{
       sku: "FIN-LAM-M",
       name: "Lamination film — matte 30µm",
       unit: "m",
       cost_price: "0.17",
       sales_price: "0.50",
       minimum_stock: "100",
       opening_stock: "400"
     },
     %{
       sku: "FIN-WIREO",
       name: "Wire-o binding spine 3:1",
       unit: "pieces",
       cost_price: "0.20",
       sales_price: "0.70",
       minimum_stock: "200",
       opening_stock: "1000"
     }
   ]},
  {"Consumables",
   [
     %{
       sku: "CON-STAPLE",
       name: "Saddle-stitch staples",
       unit: "pieces",
       cost_price: "0.004",
       minimum_stock: "5000",
       opening_stock: "20000"
     },
     %{
       sku: "CON-GROM",
       name: "Banner eyelets / grommets",
       unit: "pieces",
       cost_price: "0.08",
       sales_price: "0.30",
       minimum_stock: "200",
       opening_stock: "1000"
     },
     %{
       sku: "CON-TAPE",
       name: "Double-sided mounting tape",
       unit: "roll",
       cost_price: "4.00",
       minimum_stock: "5",
       opening_stock: "20"
     }
   ]}
]

{created, existing} =
  Enum.reduce(inventory, {0, 0}, fn {category_name, materials}, acc ->
    category = ensure_category.(category_name)

    Enum.reduce(materials, acc, fn attrs, {created, existing} ->
      case ensure_material.(Map.put(attrs, :category_id, category.id)) do
        :created -> {created + 1, existing}
        :exists -> {created, existing + 1}
      end
    end)
  end)

IO.puts(
  "Inventory seed: #{created} material(s) created, #{existing} already present " <>
    "across #{length(inventory)} categories."
)
