defmodule Productionflow.OrdersTest do
  use Productionflow.DataCase, async: true

  import Productionflow.CatalogFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.InventoryFixtures
  import Productionflow.CRMFixtures
  import Productionflow.OrdersFixtures

  alias Productionflow.{Orders, Inventory}
  alias Productionflow.Orders.Order

  # A template costing €1.05/unit at qty 100: a €5/hour machine doing 1 hour, plus
  # 50 units of a €2 material. The material starts with 1000 in stock.
  defp priced_setup(_ctx) do
    template = product_template_fixture(%{name: "A5 flyer", output_unit: "flyer"})

    machine =
      machine_fixture(%{
        units_per_hour: Decimal.new(100),
        setup_minutes: Decimal.new(0),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(3_000),
        productive_hours_per_year: Decimal.new(1_000)
      })

    material = material_fixture(%{cost_price: Decimal.new(2), opening_stock: Decimal.new(1000)})
    route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})

    template_material_fixture(template, material, %{quantity_per_unit: Decimal.new("0.5")})

    %{template: Productionflow.Catalog.get_product_template!(template.id), material: material}
  end

  defp confirmed_in_production(order) do
    {:ok, order} = Orders.transition_order(order, :confirmed)
    {:ok, order} = Orders.transition_order(order, :in_production)
    order
  end

  describe "numbering" do
    test "per-year mode numbers ORD-<year>-0001, incrementing" do
      year = Date.utc_today().year
      o1 = order_fixture()
      o2 = order_fixture()
      assert o1.number == "ORD-#{year}-0001"
      assert o2.number == "ORD-#{year}-0002"
    end

    test "continuous mode drops the year" do
      Orders.update_settings(%{number_mode: :continuous})
      assert order_fixture().number == "ORD-0001"
    end

    test "a custom prefix is honoured" do
      Orders.update_settings(%{number_prefix: "JOB"})
      assert order_fixture().number =~ ~r/^JOB-/
    end
  end

  describe "create_order/1" do
    test "creates a draft order for a customer" do
      relation = relation_fixture()
      assert {:ok, order} = Orders.create_order(%{"relation_id" => relation.id})
      assert order.status == :draft
      assert order.order_date == Date.utc_today()
    end

    test "requires a customer" do
      assert {:error, changeset} = Orders.create_order(%{})
      assert %{relation_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "add_line_from_template/3" do
    setup :priced_setup

    test "snapshots price/cost/margin and copies route + materials", %{template: template} do
      order = order_fixture()
      assert {:ok, line} = Orders.add_line_from_template(order, template.id, "100")

      assert line.description == "A5 flyer"
      assert Decimal.equal?(line.quantity, Decimal.new("100"))
      assert Decimal.equal?(line.internal_total_cost, Decimal.new("105"))
      assert Decimal.equal?(line.unit_price, Decimal.new("1.05"))
      assert line.price_source == :calculated
      assert length(line.route_steps) == 1
      assert length(line.materials) == 1
      assert Decimal.equal?(hd(line.materials).quantity, Decimal.new("50"))
    end

    test "is rejected once the order leaves draft", %{template: template} do
      order = order_fixture() |> confirmed_in_production()
      assert {:error, :not_draft} = Orders.add_line_from_template(order, template.id, "100")
    end
  end

  describe "status transitions" do
    test "legal path draft → confirmed → in_production" do
      order = order_fixture()
      assert {:ok, %Order{status: :confirmed} = o} = Orders.transition_order(order, :confirmed)
      assert {:ok, %Order{status: :in_production}} = Orders.transition_order(o, :in_production)
    end

    test "illegal jumps are rejected" do
      order = order_fixture()
      assert {:error, changeset} = Orders.transition_order(order, :completed)
      assert %{status: [_]} = errors_on(changeset)
    end

    test "an order can be cancelled from a non-terminal state" do
      order = order_fixture()
      assert {:ok, %Order{status: :cancelled}} = Orders.cancel_order(order)
    end

    test "update_order only works while draft" do
      order = order_fixture()
      assert {:ok, _} = Orders.update_order(order, %{reference: "PO-1"})
      {:ok, order} = Orders.transition_order(order, :confirmed)
      assert {:error, :not_draft} = Orders.update_order(order, %{reference: "PO-2"})
    end
  end

  describe "route steps & completion" do
    setup :priced_setup

    test "steps only advance while the order is in production", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      step = hd(line.route_steps)

      assert {:error, :order_not_in_production} = Orders.advance_step(step, :in_progress)

      order = confirmed_in_production(order)
      assert order.status == :in_production
      assert {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
    end

    test "illegal step transitions are rejected", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      confirmed_in_production(order)
      step = Orders.get_route_step!(hd(line.route_steps).id)

      assert {:error, changeset} = Orders.advance_step(step, :done)
      assert %{status: [_]} = errors_on(changeset)
    end

    test "cannot complete until every step is done", %{template: template} do
      order = order_fixture()
      Orders.add_line_from_template(order, template.id, "100")
      order = confirmed_in_production(order)

      assert {:error, :steps_unfinished} = Orders.complete_order(order, nil)
    end

    test "completing consumes the line materials' stock", %{
      template: template,
      material: material
    } do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      order = confirmed_in_production(order)

      for step <- line.route_steps do
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :done)
      end

      before = Inventory.get_material!(material.id).current_stock
      assert {:ok, %Order{status: :completed}} = Orders.complete_order(order, nil)
      after_stock = Inventory.get_material!(material.id).current_stock

      # consumed 50 units
      assert Decimal.equal?(Decimal.sub(before, after_stock), Decimal.new("50"))
      assert hd(Orders.get_line!(line.id).materials).consumed_at
    end

    test "consumption is allowed to drive stock negative" do
      template = product_template_fixture()
      machine = machine_fixture()
      material = material_fixture(%{cost_price: Decimal.new(1)})
      route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
      template_material_fixture(template, material, %{quantity_per_unit: Decimal.new(1)})
      template = Productionflow.Catalog.get_product_template!(template.id)

      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "10")
      order = confirmed_in_production(order)

      for step <- line.route_steps do
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :done)
      end

      assert {:ok, _} = Orders.complete_order(order, nil)
      assert Decimal.compare(Inventory.get_material!(material.id).current_stock, 0) == :lt
    end
  end

  describe "line_status/1 & delete_line/1" do
    setup :priced_setup

    test "line status derives from its steps", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      assert Orders.line_status(line) == :pending

      confirmed_in_production(order)
      step = hd(line.route_steps)
      {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
      assert Orders.line_status(Orders.get_line!(line.id)) == :in_progress
    end

    test "lines can only be removed while draft", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      assert {:ok, _} = Orders.delete_line(Orders.get_line!(line.id))

      {:ok, line2} = Orders.add_line_from_template(order, template.id, "100")
      confirmed_in_production(order)
      assert {:error, :not_draft} = Orders.delete_line(Orders.get_line!(line2.id))
    end
  end

  describe "ad-hoc lines" do
    defp ad_hoc_machine do
      machine_fixture(%{
        units_per_hour: Decimal.new(100),
        setup_minutes: Decimal.new(0),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(3_000),
        productive_hours_per_year: Decimal.new(1_000)
      })
    end

    test "builds cost from its own steps + materials, price from default margin" do
      order = order_fixture()

      {:ok, line} =
        Orders.add_blank_line(order, %{
          "description" => "Custom box",
          "output_unit" => "box",
          "quantity" => "10"
        })

      assert line.price_source == :calculated

      {:ok, line} =
        Orders.add_line_route_step(line, %{
          "machine_id" => ad_hoc_machine().id,
          "machine_quantity" => "100"
        })

      material = material_fixture(%{cost_price: Decimal.new(2)})

      {:ok, line} =
        Orders.add_line_material(line, %{"material_id" => material.id, "quantity" => "50"})

      # machine €5 + material €100 = €105
      assert Decimal.equal?(line.internal_total_cost, Decimal.new("105"))
      assert length(line.route_steps) == 1
      assert length(line.materials) == 1
    end

    test "a manual unit price overrides the calculated one" do
      order = order_fixture()

      {:ok, line} =
        Orders.add_blank_line(order, %{
          "description" => "Assembly",
          "quantity" => "10",
          "unit_price" => "25"
        })

      assert line.price_source == :manual
      assert Decimal.equal?(line.unit_price, Decimal.new("25"))
      assert Decimal.equal?(line.total_price, Decimal.new("250"))
    end

    test "route/material editing is rejected on template-based lines", %{} do
      template = product_template_fixture(%{output_unit: "flyer"})
      route_step_fixture(template, ad_hoc_machine(), %{quantity_per_unit: Decimal.new(1)})
      template = Productionflow.Catalog.get_product_template!(template.id)

      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "10")

      assert {:error, :not_ad_hoc} =
               Orders.add_line_route_step(line, %{
                 "machine_id" => ad_hoc_machine().id,
                 "machine_quantity" => "1"
               })
    end

    test "deleting a step recomputes the line cost" do
      order = order_fixture()
      {:ok, line} = Orders.add_blank_line(order, %{"description" => "X", "quantity" => "10"})

      {:ok, line} =
        Orders.add_line_route_step(line, %{
          "machine_id" => ad_hoc_machine().id,
          "machine_quantity" => "100"
        })

      assert Decimal.compare(line.internal_total_cost, 0) == :gt
      {:ok, line} = Orders.delete_line_route_step(hd(line.route_steps))
      assert Decimal.equal?(line.internal_total_cost, Decimal.new("0"))
    end
  end

  describe "line dependencies" do
    setup :priced_setup

    test "a line is blocked until its dependency is done", %{template: template} do
      order = order_fixture()
      {:ok, a} = Orders.add_line_from_template(order, template.id, "100")
      {:ok, b} = Orders.add_line_from_template(order, template.id, "100")

      assert {:ok, _} = Orders.set_line_dependencies(b, [a.id])
      assert Orders.line_status(Orders.get_line!(b.id)) == :blocked

      order = confirmed_in_production(order)
      assert order.status == :in_production

      b_step = hd(Orders.get_line!(b.id).route_steps)
      assert {:error, :line_blocked} = Orders.advance_step(b_step, :in_progress)

      # Finish A, then B unblocks.
      for step <- Orders.get_line!(a.id).route_steps do
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
        {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :done)
      end

      assert Orders.line_status(Orders.get_line!(b.id)) == :pending
      assert {:ok, _} = Orders.advance_step(Orders.get_route_step!(b_step.id), :in_progress)
    end

    test "dependencies can only be set while draft", %{template: template} do
      order = order_fixture()
      {:ok, a} = Orders.add_line_from_template(order, template.id, "100")
      {:ok, b} = Orders.add_line_from_template(order, template.id, "100")
      confirmed_in_production(order)

      assert {:error, :not_draft} = Orders.set_line_dependencies(Orders.get_line!(b.id), [a.id])
    end
  end
end
