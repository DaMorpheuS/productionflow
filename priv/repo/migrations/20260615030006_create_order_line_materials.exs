defmodule Productionflow.Repo.Migrations.CreateOrderLineMaterials do
  use Ecto.Migration

  def change do
    create table(:order_line_materials) do
      add :order_line_id, references(:order_lines, on_delete: :delete_all), null: false
      add :material_id, references(:materials, on_delete: :restrict), null: false
      add :material_name, :string, null: false
      add :unit, :string
      add :quantity, :decimal, precision: 12, scale: 4, null: false
      add :unit_cost, :decimal, precision: 12, scale: 4
      add :cost, :decimal, precision: 12, scale: 4
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:order_line_materials, [:order_line_id])
    create index(:order_line_materials, [:material_id])
  end
end
