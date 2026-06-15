defmodule Productionflow.Repo.Migrations.PriceListScopeBuckets do
  use Ecto.Migration

  # Price lists are no longer named, user-created containers: each is an
  # automatic scope bucket — one general list plus one per customer — created on
  # demand and managed from the product. Drop the now-unused name/active/archived
  # columns and enforce a single bucket per customer.
  def change do
    alter table(:price_lists) do
      remove :name, :string
      remove :active, :boolean, null: false, default: true
      remove :archived_at, :utc_datetime
    end

    create unique_index(:price_lists, [:relation_id],
             where: "relation_id IS NOT NULL",
             name: :price_lists_customer_index
           )
  end
end
