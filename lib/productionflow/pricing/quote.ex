defmodule Productionflow.Pricing.Quote do
  @moduledoc """
  Non-persisted result of pricing a product template at a quantity for an
  optional customer. Wraps the internal `Productionflow.Catalog.CostEstimate`
  and resolves a customer-facing price, keeping the margin visible.

  `price_source` is `:price_list` when a matching price-list item was resolved,
  otherwise `:calculated` (the default margin applied to internal cost).

  Cost-derived fields (`internal_unit_cost`, `internal_total_cost`,
  `default_unit_price`, `unit_margin`, `total_margin`, `margin_pct_of_price`)
  are `nil` when the template's machine cost basis is incomplete (see
  `Productionflow.Catalog.estimate/2`). `below_cost?` is `false` whenever the
  margin is unknown.
  """

  defstruct template: nil,
            quantity: Decimal.new(0),
            relation: nil,
            estimate: nil,
            internal_unit_cost: nil,
            internal_total_cost: nil,
            effective_margin_pct: Decimal.new(0),
            default_unit_price: nil,
            price_source: :calculated,
            price_list_item: nil,
            unit_price: nil,
            total_price: nil,
            unit_margin: nil,
            total_margin: nil,
            margin_pct_of_price: nil,
            below_cost?: false
end
