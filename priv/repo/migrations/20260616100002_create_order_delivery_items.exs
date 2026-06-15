defmodule Productionflow.Repo.Migrations.CreateOrderDeliveryItems do
  use Ecto.Migration

  def change do
    create table(:order_delivery_items) do
      add :order_delivery_id, references(:order_deliveries, on_delete: :delete_all), null: false
      add :order_line_id, references(:order_lines, on_delete: :delete_all), null: false
      add :quantity, :decimal, precision: 12, scale: 4, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:order_delivery_items, [:order_delivery_id, :order_line_id])
    create index(:order_delivery_items, [:order_line_id])
  end
end
