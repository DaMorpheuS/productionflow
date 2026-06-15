defmodule Productionflow.Repo.Migrations.CreatePriceListItems do
  use Ecto.Migration

  def change do
    create table(:price_list_items) do
      add :price_list_id, references(:price_lists, on_delete: :delete_all), null: false
      add :product_template_id, references(:product_templates, on_delete: :restrict), null: false
      add :min_quantity, :decimal, precision: 12, scale: 4, null: false, default: 1
      add :kind, :string, null: false, default: "fixed_price"
      add :unit_price, :decimal, precision: 12, scale: 4
      add :discount_pct, :decimal, precision: 12, scale: 4

      timestamps(type: :utc_datetime)
    end

    create index(:price_list_items, [:price_list_id])
    create index(:price_list_items, [:product_template_id])

    create unique_index(:price_list_items, [:price_list_id, :product_template_id, :min_quantity],
             name: :price_list_items_tier_index
           )
  end
end
