defmodule Productionflow.Pricing.PriceList do
  @moduledoc """
  A price-list scope bucket: either general (no relation) or bound to one
  customer. Buckets are created on demand from a product and hold the product's
  price tiers (`PriceListItem`); there is at most one general bucket and one per
  customer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "price_lists" do
    belongs_to :relation, Productionflow.CRM.Relation

    has_many :items, Productionflow.Pricing.PriceListItem,
      foreign_key: :price_list_id,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(price_list, attrs) do
    price_list
    |> cast(attrs, [:relation_id])
    |> assoc_constraint(:relation)
    |> unique_constraint(:relation_id,
      name: :price_lists_customer_index,
      message: "a price list for this customer already exists"
    )
  end
end
