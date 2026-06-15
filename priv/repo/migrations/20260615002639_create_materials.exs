defmodule Productionflow.Repo.Migrations.CreateMaterials do
  use Ecto.Migration

  def change do
    create table(:materials) do
      add :name, :string, null: false
      add :sku, :string
      add :supplier_code, :string
      add :supplier_id, references(:relations, on_delete: :nilify_all)
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :unit, :string, null: false
      add :cost_price, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :sales_price, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :current_stock, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :minimum_stock, :decimal, precision: 12, scale: 4
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:materials, [:name])
    create index(:materials, [:supplier_id])
    create index(:materials, [:category_id])
    create unique_index(:materials, [:sku], where: "sku IS NOT NULL")
  end
end
