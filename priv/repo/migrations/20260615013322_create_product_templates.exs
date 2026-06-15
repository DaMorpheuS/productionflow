defmodule Productionflow.Repo.Migrations.CreateProductTemplates do
  use Ecto.Migration

  def change do
    create table(:product_templates) do
      add :name, :string, null: false
      add :sku, :string
      add :output_unit, :string, null: false
      add :description, :text
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:product_templates, [:name])
    create unique_index(:product_templates, [:sku], where: "sku IS NOT NULL")
  end
end
