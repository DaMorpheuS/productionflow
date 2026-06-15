defmodule Productionflow.PricingFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.Pricing` context.
  """

  alias Productionflow.Pricing

  @doc """
  Adds a price tier to a product. Pass `scope_relation_id` (a customer id) for a
  customer-bound tier; omit it for a general one. Other keys override the
  fixed-price defaults.
  """
  def price_tier_fixture(template, attrs \\ %{}) do
    attrs =
      %{
        "scope_relation_id" => "",
        "min_quantity" => "1",
        "kind" => "fixed_price",
        "unit_price" => "1.00"
      }
      |> Map.merge(stringify_keys(attrs))

    {:ok, item} = Pricing.add_template_price_tier(template, attrs)
    item
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
