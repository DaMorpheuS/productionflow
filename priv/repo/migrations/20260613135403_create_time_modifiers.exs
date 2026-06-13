defmodule Productionflow.Repo.Migrations.CreateTimeModifiers do
  use Ecto.Migration

  def change do
    create table(:time_modifiers) do
      add :machine_id, references(:machines, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :value, :decimal, precision: 12, scale: 4, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:time_modifiers, [:machine_id])
  end
end
