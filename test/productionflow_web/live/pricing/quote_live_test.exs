defmodule ProductionflowWeb.Pricing.QuoteLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CatalogFixtures
  import Productionflow.PricingFixtures
  import Productionflow.ProductionFixtures

  alias Productionflow.Catalog

  # €5.00/hour, 100 units/hour → €0.05/unit.
  defp priced_template do
    template = product_template_fixture(%{output_unit: "flyer"})

    machine =
      machine_fixture(%{
        units_per_hour: Decimal.new(100),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(3_000),
        productive_hours_per_year: Decimal.new(1_000)
      })

    route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
    Catalog.get_product_template!(template.id)
  end

  defp change_quote(lv, template, qty) do
    lv
    |> form("#quote-form", %{
      "template_id" => to_string(template.id),
      "quantity" => qty,
      "relation_id" => ""
    })
    |> render_change()
  end

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/pricing/quote")
    end
  end

  describe "Quote" do
    setup [:register_and_log_in_user]

    @tag permissions: ["pricing.view"]
    test "shows the calculated price when no price list applies", %{conn: conn} do
      template = priced_template()

      {:ok, lv, _html} = live(conn, ~p"/pricing/quote")
      html = change_quote(lv, template, "100")

      assert html =~ "Calculated (margin)"
      # internal cost per unit €0.05
      assert html =~ "€0.05"
    end

    @tag permissions: ["pricing.view"]
    test "resolves a price-list tier and flags a below-cost price", %{conn: conn} do
      template = priced_template()
      price_tier_fixture(template, %{min_quantity: Decimal.new(1), unit_price: "0.01"})

      {:ok, lv, _html} = live(conn, ~p"/pricing/quote")
      html = change_quote(lv, template, "100")

      assert html =~ "Price list"
      assert html =~ "below internal cost"
    end
  end
end
