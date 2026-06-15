defmodule Productionflow.Pricing.PriceListItem do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:fixed_price, :discount_percent]

  schema "price_list_items" do
    field :min_quantity, :decimal, default: Decimal.new(1)
    field :kind, Ecto.Enum, values: @kinds, default: :fixed_price
    field :unit_price, :decimal
    field :discount_pct, :decimal

    # The scope chosen when adding a tier from a product: nil = general,
    # otherwise the customer's relation id. Resolves to a price-list bucket; not
    # persisted on the item itself.
    field :scope_relation_id, :integer, virtual: true

    belongs_to :price_list, Productionflow.Pricing.PriceList
    belongs_to :product_template, Productionflow.Catalog.ProductTemplate

    timestamps(type: :utc_datetime)
  end

  @doc "The supported item kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :product_template_id,
      :min_quantity,
      :kind,
      :unit_price,
      :discount_pct,
      :scope_relation_id
    ])
    |> validate_required([:product_template_id, :min_quantity, :kind])
    |> validate_number(:min_quantity, greater_than: 0)
    |> validate_by_kind()
    |> assoc_constraint(:product_template)
    |> unique_constraint(:min_quantity,
      name: :price_list_items_tier_index,
      message: "a tier for this product at this quantity already exists"
    )
  end

  # A fixed-price item carries an absolute unit price; a discount item carries a
  # percentage off the calculated (margin-based) sales price. The unused field is
  # cleared so stale values don't leak into pricing.
  defp validate_by_kind(changeset) do
    case get_field(changeset, :kind) do
      :fixed_price ->
        changeset
        |> put_change(:discount_pct, nil)
        |> validate_required([:unit_price])
        |> validate_number(:unit_price, greater_than_or_equal_to: 0)

      :discount_percent ->
        changeset
        |> put_change(:unit_price, nil)
        |> validate_required([:discount_pct])
        |> validate_number(:discount_pct,
          greater_than_or_equal_to: 0,
          less_than_or_equal_to: 100
        )

      _ ->
        changeset
    end
  end
end
