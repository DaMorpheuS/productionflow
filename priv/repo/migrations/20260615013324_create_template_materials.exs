defmodule Productionflow.Repo.Migrations.CreateTemplateMaterials do
  use Ecto.Migration

  def change do
    create table(:template_materials) do
      add :product_template_id, references(:product_templates, on_delete: :delete_all),
        null: false

      add :material_id, references(:materials, on_delete: :restrict), null: false
      add :quantity_per_unit, :decimal, precision: 12, scale: 4, null: false
      add :waste_pct, :decimal, precision: 12, scale: 4, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:template_materials, [:product_template_id])
    create index(:template_materials, [:material_id])
  end
end
