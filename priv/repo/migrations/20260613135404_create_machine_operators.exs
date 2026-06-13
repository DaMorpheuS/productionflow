defmodule Productionflow.Repo.Migrations.CreateMachineOperators do
  use Ecto.Migration

  def change do
    create table(:machine_operators) do
      add :machine_id, references(:machines, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create unique_index(:machine_operators, [:machine_id, :user_id])
    create index(:machine_operators, [:user_id])
  end
end
