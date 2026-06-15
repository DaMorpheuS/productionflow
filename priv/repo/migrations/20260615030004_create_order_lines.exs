defmodule Productionflow.Repo.Migrations.CreateOrderLines do
  use Ecto.Migration

  def change do
    create table(:order_lines) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :product_template_id, references(:product_templates, on_delete: :restrict)
      add :position, :integer, null: false, default: 0
      add :description, :string, null: false
      add :output_unit, :string
      add :quantity, :decimal, precision: 12, scale: 4, null: false

      # Price/cost/margin snapshots (frozen once the order leaves :draft).
      add :unit_price, :decimal, precision: 12, scale: 4
      add :total_price, :decimal, precision: 12, scale: 4
      add :internal_unit_cost, :decimal, precision: 12, scale: 4
      add :internal_total_cost, :decimal, precision: 12, scale: 4
      add :unit_margin, :decimal, precision: 12, scale: 4
      add :total_margin, :decimal, precision: 12, scale: 4
      add :price_source, :string

      timestamps(type: :utc_datetime)
    end

    create index(:order_lines, [:order_id])
    create index(:order_lines, [:product_template_id])
  end
end
