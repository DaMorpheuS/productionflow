defmodule Productionflow.Repo.Migrations.CreatePlanningSettings do
  use Ecto.Migration

  def change do
    create table(:planning_settings) do
      add :schedule_from, :date

      timestamps(type: :utc_datetime)
    end
  end
end
