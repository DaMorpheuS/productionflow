defmodule Productionflow.Repo.Migrations.CreateMaterialTypes do
  use Ecto.Migration

  def change do
    create table(:material_types) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:material_types, [:name])
  end
end
