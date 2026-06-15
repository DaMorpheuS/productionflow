defmodule Productionflow.PricingTest do
  use Productionflow.DataCase, async: true

  import Productionflow.CatalogFixtures
  import Productionflow.PricingFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.CRMFixtures

  alias Productionflow.{Pricing, Catalog}
  alias Productionflow.Pricing.{Settings, Quote}

  # A machine whose cost basis yields €5.00/hour: (10000/5 + 3000) / 1000, and
  # produces 100 units/hour, so a template using it costs €0.05/unit.
  defp priced_template do
    template = product_template_fixture(%{output_unit: "flyer"})

    machine =
      machine_fixture(%{
        units_per_hour: Decimal.new(100),
        setup_minutes: Decimal.new(0),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(3_000),
        productive_hours_per_year: Decimal.new(1_000)
      })

    route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
    Catalog.get_product_template!(template.id)
  end

  describe "settings (singleton)" do
    test "get_settings creates and returns the singleton" do
      assert %Settings{id: 1} = Pricing.get_settings()
    end

    test "update_settings sets the default margin" do
      assert {:ok, settings} = Pricing.update_settings(%{default_margin_pct: "40"})
      assert Decimal.equal?(settings.default_margin_pct, Decimal.new("40"))
    end

    test "default margin cannot be negative" do
      assert {:error, changeset} = Pricing.update_settings(%{default_margin_pct: "-1"})
      assert %{default_margin_pct: [_]} = errors_on(changeset)
    end
  end

  describe "default_unit_price/2" do
    test "applies markup on cost" do
      assert Decimal.equal?(
               Pricing.default_unit_price(Decimal.new("10"), Decimal.new("30")),
               Decimal.new("13")
             )
    end

    test "is nil when cost is unknown" do
      assert Pricing.default_unit_price(nil, Decimal.new("30")) == nil
    end
  end

  describe "margin_pct/2" do
    test "prefers the template override over the global default" do
      settings = %Settings{default_margin_pct: Decimal.new("20")}
      assert Decimal.equal?(Pricing.margin_pct(%{margin_pct: nil}, settings), Decimal.new("20"))

      assert Decimal.equal?(
               Pricing.margin_pct(%{margin_pct: Decimal.new("35")}, settings),
               Decimal.new("35")
             )
    end
  end

  describe "adding price tiers" do
    test "creates the scope bucket on demand and reuses it" do
      template = product_template_fixture()
      customer = relation_fixture()

      price_tier_fixture(template, %{min_quantity: Decimal.new(1)})
      price_tier_fixture(template, %{min_quantity: Decimal.new(100)})

      price_tier_fixture(template, %{scope_relation_id: customer.id, min_quantity: Decimal.new(1)})

      tiers = Pricing.template_price_tiers(template)
      assert length(tiers) == 3
      # General first (relation_id nil), then the customer bucket.
      assert [nil, nil, _] = Enum.map(tiers, & &1.price_list.relation_id)
    end

    test "fixed_price requires a unit price and clears any discount" do
      template = product_template_fixture()

      assert {:error, cs} =
               Pricing.add_template_price_tier(template, %{
                 "kind" => "fixed_price",
                 "min_quantity" => "1",
                 "scope_relation_id" => ""
               })

      assert %{unit_price: ["can't be blank"]} = errors_on(cs)

      assert {:ok, item} =
               Pricing.add_template_price_tier(template, %{
                 "kind" => "fixed_price",
                 "min_quantity" => "1",
                 "unit_price" => "2.00",
                 "discount_pct" => "10",
                 "scope_relation_id" => ""
               })

      assert item.discount_pct == nil
    end

    test "discount_percent requires a percentage in 0..100" do
      template = product_template_fixture()

      assert {:error, cs} =
               Pricing.add_template_price_tier(template, %{
                 "kind" => "discount_percent",
                 "min_quantity" => "1",
                 "discount_pct" => "150",
                 "scope_relation_id" => ""
               })

      assert %{discount_pct: [_]} = errors_on(cs)
    end

    test "rejects a duplicate tier for the same product at the same quantity" do
      template = product_template_fixture()
      price_tier_fixture(template, %{min_quantity: Decimal.new(1)})

      assert {:error, cs} =
               Pricing.add_template_price_tier(template, %{
                 "kind" => "fixed_price",
                 "min_quantity" => "1",
                 "unit_price" => "3.00",
                 "scope_relation_id" => ""
               })

      assert %{min_quantity: [_]} = errors_on(cs)
    end
  end

  describe "resolve_item/3" do
    setup do
      template = product_template_fixture()
      price_tier_fixture(template, %{min_quantity: Decimal.new(1), unit_price: "1.00"})
      price_tier_fixture(template, %{min_quantity: Decimal.new(100), unit_price: "0.50"})
      %{template: template}
    end

    test "picks the highest tier whose min_quantity ≤ qty", %{template: template} do
      assert Decimal.equal?(tier(template, 1), Decimal.new("1.00"))
      assert Decimal.equal?(tier(template, 99), Decimal.new("1.00"))
      assert Decimal.equal?(tier(template, 100), Decimal.new("0.50"))
      assert Decimal.equal?(tier(template, 5000), Decimal.new("0.50"))
    end

    test "returns nil when qty is below the lowest tier" do
      other = product_template_fixture()
      price_tier_fixture(other, %{min_quantity: Decimal.new(10), unit_price: "1.00"})
      assert Pricing.resolve_item(other, 5) == nil
    end

    test "a relation-bound tier beats a general one", %{template: template} do
      customer = relation_fixture()

      price_tier_fixture(template, %{
        scope_relation_id: customer.id,
        min_quantity: Decimal.new(1),
        unit_price: "0.80"
      })

      assert Decimal.equal?(Pricing.resolve_item(template, 100, customer).unit_price, "0.80")
      # No relation → general tiers only.
      assert Decimal.equal?(Pricing.resolve_item(template, 100).unit_price, "0.50")
    end

    defp tier(template, qty), do: Pricing.resolve_item(template, qty).unit_price
  end

  describe "quote/3" do
    test "calculated source applies the default margin to cost" do
      Pricing.update_settings(%{default_margin_pct: "100"})
      template = priced_template()

      assert %Quote{} = q = Pricing.quote(template, 100)
      assert q.price_source == :calculated
      assert Decimal.equal?(q.internal_unit_cost, Decimal.new("0.05"))
      assert Decimal.equal?(q.default_unit_price, Decimal.new("0.10"))
      assert Decimal.equal?(q.unit_price, Decimal.new("0.10"))
      assert Decimal.equal?(q.total_price, Decimal.new("10"))
      assert Decimal.equal?(q.unit_margin, Decimal.new("0.05"))
      refute q.below_cost?
    end

    test "a price-list tier overrides the calculated price" do
      template = priced_template()
      price_tier_fixture(template, %{min_quantity: Decimal.new(1), unit_price: "0.20"})

      q = Pricing.quote(template, 100)
      assert q.price_source == :price_list
      assert Decimal.equal?(q.unit_price, Decimal.new("0.20"))
      assert Decimal.equal?(q.internal_unit_cost, Decimal.new("0.05"))
    end

    test "a discount tier discounts the default price" do
      Pricing.update_settings(%{default_margin_pct: "100"})
      template = priced_template()

      price_tier_fixture(template, %{
        kind: "discount_percent",
        min_quantity: Decimal.new(1),
        discount_pct: Decimal.new(10)
      })

      q = Pricing.quote(template, 100)
      # default 0.10 less 10% → 0.09
      assert Decimal.equal?(q.unit_price, Decimal.new("0.09"))
    end

    test "flags a price below internal cost" do
      template = priced_template()
      price_tier_fixture(template, %{min_quantity: Decimal.new(1), unit_price: "0.01"})

      q = Pricing.quote(template, 100)
      assert q.below_cost?
      assert Decimal.compare(q.unit_margin, 0) == :lt
    end

    test "handles an incomplete cost basis: price without margin" do
      template = product_template_fixture()
      machine = machine_fixture()
      route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
      template = Catalog.get_product_template!(template.id)

      price_tier_fixture(template, %{min_quantity: Decimal.new(1), unit_price: "0.20"})

      q = Pricing.quote(template, 100)
      assert q.internal_unit_cost == nil
      assert q.default_unit_price == nil
      assert Decimal.equal?(q.unit_price, Decimal.new("0.20"))
      assert q.unit_margin == nil
      refute q.below_cost?
    end
  end
end
