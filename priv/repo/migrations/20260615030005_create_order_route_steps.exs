defmodule Productionflow.Repo.Migrations.CreateOrderRouteSteps do
  use Ecto.Migration

  def change do
    create table(:order_route_steps) do
      add :order_line_id, references(:order_lines, on_delete: :delete_all), null: false
      add :machine_id, references(:machines, on_delete: :restrict), null: false
      add :machine_name, :string, null: false
      add :position, :integer, null: false, default: 0
      add :quantity_per_unit, :decimal, precision: 12, scale: 4, null: false, default: 1
      add :machine_quantity, :decimal, precision: 12, scale: 4

      # Duration/cost snapshots; machine_cost is null when the basis is incomplete.
      add :duration_minutes, :decimal, precision: 12, scale: 4
      add :machine_cost, :decimal, precision: 12, scale: 4
      add :labour_cost, :decimal, precision: 12, scale: 4
      add :energy_cost, :decimal, precision: 12, scale: 4

      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:order_route_steps, [:order_line_id])
    create index(:order_route_steps, [:machine_id])
  end
end
