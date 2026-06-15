defmodule Productionflow.Repo.Migrations.CreateStockMovements do
  use Ecto.Migration

  def change do
    create table(:stock_movements) do
      add :material_id, references(:materials, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :quantity, :decimal, precision: 12, scale: 4, null: false
      add :unit_cost, :decimal, precision: 12, scale: 4
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:stock_movements, [:material_id])
    create index(:stock_movements, [:inserted_at])
  end
end
