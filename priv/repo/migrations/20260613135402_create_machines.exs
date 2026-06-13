defmodule Productionflow.Repo.Migrations.CreateMachines do
  use Ecto.Migration

  def change do
    create table(:machines) do
      add :name, :string, null: false
      add :output_unit, :string, null: false
      add :units_per_hour, :decimal, precision: 12, scale: 4, null: false
      add :setup_minutes, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :power_kw, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :purchase_price, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :residual_value, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :yearly_maintenance_cost, :decimal, precision: 12, scale: 4, null: false, default: 0
      add :lifetime_years, :decimal, precision: 12, scale: 4
      add :productive_hours_per_year, :decimal, precision: 12, scale: 4
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:machines, [:name])
  end
end
