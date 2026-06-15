defmodule Productionflow.Repo.Migrations.AlterMaterialsAddTypeAndAttributes do
  use Ecto.Migration

  def change do
    alter table(:materials) do
      add :material_type_id, references(:material_types, on_delete: :nilify_all)
      add :attributes, :map, null: false, default: %{}
    end

    create index(:materials, [:material_type_id])
  end
end
