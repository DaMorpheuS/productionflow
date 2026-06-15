defmodule Productionflow.Repo.Migrations.CreateRouteSteps do
  use Ecto.Migration

  def change do
    create table(:route_steps) do
      add :product_template_id, references(:product_templates, on_delete: :delete_all),
        null: false

      add :machine_id, references(:machines, on_delete: :restrict), null: false
      add :position, :integer, null: false, default: 0
      add :quantity_per_unit, :decimal, precision: 12, scale: 4, null: false, default: 1
      add :time_modifier_ids, {:array, :integer}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:route_steps, [:product_template_id])
    create index(:route_steps, [:machine_id])
  end
end
