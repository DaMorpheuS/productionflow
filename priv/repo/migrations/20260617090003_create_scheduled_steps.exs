defmodule Productionflow.Repo.Migrations.CreateScheduledSteps do
  use Ecto.Migration

  def change do
    create table(:scheduled_steps) do
      add :order_route_step_id, references(:order_route_steps, on_delete: :delete_all),
        null: false

      add :machine_id, references(:machines, on_delete: :restrict), null: false
      add :position, :integer, null: false, default: 0
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scheduled_steps, [:order_route_step_id])
    create index(:scheduled_steps, [:machine_id])
  end
end
