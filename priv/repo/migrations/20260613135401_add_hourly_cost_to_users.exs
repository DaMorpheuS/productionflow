defmodule Productionflow.Repo.Migrations.AddHourlyCostToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hourly_cost, :decimal, precision: 12, scale: 4, null: false, default: 0
    end
  end
end
