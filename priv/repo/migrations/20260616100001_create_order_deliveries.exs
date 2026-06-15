defmodule Productionflow.Repo.Migrations.CreateOrderDeliveries do
  use Ecto.Migration

  def change do
    create table(:order_deliveries) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :address_id, references(:addresses, on_delete: :nilify_all)
      add :street, :string, null: false
      add :postal_code, :string
      add :city, :string, null: false
      add :country, :string
      add :planned_date, :date
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:order_deliveries, [:order_id])
    create index(:order_deliveries, [:address_id])
  end
end
