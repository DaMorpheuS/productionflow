defmodule Productionflow.Repo.Migrations.AddKindToOrderDeliveries do
  use Ecto.Migration

  # A delivery is either to an address or a customer pickup. Pickups have no
  # address, so street/city become nullable.
  def change do
    alter table(:order_deliveries) do
      add :kind, :string, null: false, default: "address"
      modify :street, :string, null: true, from: {:string, null: false}
      modify :city, :string, null: true, from: {:string, null: false}
    end
  end
end
