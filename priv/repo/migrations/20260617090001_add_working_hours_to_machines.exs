defmodule Productionflow.Repo.Migrations.AddWorkingHoursToMachines do
  use Ecto.Migration

  def change do
    alter table(:machines) do
      add :working_day_start, :time, null: false, default: "08:00:00"
      add :working_day_end, :time, null: false, default: "16:30:00"
      add :working_days, {:array, :integer}, null: false, default: [1, 2, 3, 4, 5]
    end
  end
end
