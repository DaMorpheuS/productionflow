defmodule Productionflow.Repo.Migrations.CreateFieldDefinitions do
  use Ecto.Migration

  def change do
    create table(:field_definitions) do
      add :material_type_id, references(:material_types, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :label, :string, null: false
      add :field_type, :string, null: false
      add :unit, :string
      add :options, {:array, :string}, null: false, default: []
      add :required, :boolean, null: false, default: false
      add :default_value, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:field_definitions, [:material_type_id])
    create unique_index(:field_definitions, [:material_type_id, :key])
  end
end
