defmodule Productionflow.Repo.Migrations.CreatePricingSettings do
  use Ecto.Migration

  def change do
    create table(:pricing_settings) do
      add :default_margin_pct, :decimal, precision: 12, scale: 4, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # Seed the singleton row (id = 1).
    execute(
      "INSERT INTO pricing_settings (id, default_margin_pct, inserted_at, updated_at) VALUES (1, 0, now(), now())",
      "DELETE FROM pricing_settings WHERE id = 1"
    )
  end
end
