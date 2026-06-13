defmodule Productionflow.Repo.Migrations.CreateProductionSettings do
  use Ecto.Migration

  def change do
    create table(:production_settings) do
      add :energy_price_per_kwh, :decimal, precision: 12, scale: 4, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # Seed the singleton row (id = 1).
    execute(
      "INSERT INTO production_settings (id, energy_price_per_kwh, inserted_at, updated_at) VALUES (1, 0, now(), now())",
      "DELETE FROM production_settings WHERE id = 1"
    )
  end
end
