defmodule Productionflow.Repo.Migrations.CreateOrderSettings do
  use Ecto.Migration

  def change do
    create table(:order_settings) do
      add :number_mode, :string, null: false, default: "per_year"
      add :number_prefix, :string, null: false, default: "ORD"

      timestamps(type: :utc_datetime)
    end

    # Seed the singleton row (id = 1).
    execute(
      "INSERT INTO order_settings (id, number_mode, number_prefix, inserted_at, updated_at) VALUES (1, 'per_year', 'ORD', now(), now())",
      "DELETE FROM order_settings WHERE id = 1"
    )
  end
end
