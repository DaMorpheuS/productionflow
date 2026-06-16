defmodule Productionflow.OrdersTest do
  use Productionflow.DataCase, async: true

  import Productionflow.CatalogFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.InventoryFixtures
  import Productionflow.CRMFixtures
  import Productionflow.OrdersFixtures

  alias Productionflow.{Orders, Inventory, CRM}
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

  defp accepted_in_production(order) do
    {:ok, order} = Orders.accept_quote(order)
    {:ok, _} = Orders.add_pickup(order)
    {:ok, order} = Orders.transition_order(order, :in_production)
    order
  end

  describe "numbering" do
    test "a new quote gets a per-year quote number, no order number yet" do
      year = Date.utc_today().year
      o1 = order_fixture()
      o2 = order_fixture()
      assert o1.quote_number == "QUO-#{year}-0001"
      assert o2.quote_number == "QUO-#{year}-0002"
      assert o1.number == nil
    end

    test "continuous quote mode drops the year" do
      Orders.update_settings(%{quote_number_mode: :continuous})
      assert order_fixture().quote_number == "QUO-0001"
    end

    test "a custom quote prefix is honoured" do
      Orders.update_settings(%{quote_number_prefix: "OFF"})
      assert order_fixture().quote_number =~ ~r/^OFF-/
    end

    test "accepting assigns a per-year order number" do
      year = Date.utc_today().year
      assert {:ok, o} = Orders.accept_quote(order_fixture())
      assert o.status == :accepted
      assert o.number == "ORD-#{year}-0001"
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
      order = order_fixture() |> accepted_in_production()
      assert {:error, :not_editable} = Orders.add_line_from_template(order, template.id, "100")
    end
  end

  describe "status transitions" do
    test "legal path draft → accepted → in_production" do
      order = order_fixture()
      assert {:ok, %Order{status: :accepted} = o} = Orders.accept_quote(order)
      {:ok, _} = Orders.add_pickup(o)
      assert {:ok, %Order{status: :in_production}} = Orders.transition_order(o, :in_production)
    end

    test "production cannot start without a delivery or pickup" do
      order = order_fixture()
      {:ok, order} = Orders.accept_quote(order)
      assert {:error, :no_deliveries} = Orders.transition_order(order, :in_production)

      {:ok, _} = Orders.add_pickup(order)

      assert {:ok, %Order{status: :in_production}} =
               Orders.transition_order(order, :in_production)
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

    test "update_order works while draft or accepted, not once in production" do
      order = order_fixture()
      assert {:ok, _} = Orders.update_order(order, %{reference: "PO-1"})

      {:ok, order} = Orders.accept_quote(order)
      assert {:ok, _} = Orders.update_order(order, %{reference: "PO-2"})

      {:ok, _} = Orders.add_pickup(order)
      {:ok, order} = Orders.transition_order(order, :in_production)
      assert {:error, :not_editable} = Orders.update_order(order, %{reference: "PO-3"})
    end

    test "a quote can be sent, declined with a reason, revised and archived" do
      order = order_fixture()
      {:ok, order} = Orders.transition_order(order, :sent)
      assert order.status == :sent

      assert {:error, cs} = Orders.decline_quote(order, %{})
      assert %{decline_reason: [_]} = errors_on(cs)

      {:ok, order} =
        Orders.decline_quote(order, %{"decline_reason" => "price", "decline_notes" => "too high"})

      assert order.status == :declined
      assert order.decline_reason == :price
      assert order.decline_notes == "too high"

      assert {:error, _} = Orders.archive_order(order, "")
      {:ok, archived} = Orders.archive_order(order, "not worth re-quoting")
      assert archived.archived_at
      assert archived.archive_reason == "not worth re-quoting"

      {:ok, revised} = Orders.revise_quote(order)
      assert revised.status == :draft
      assert revised.decline_reason == nil
    end

    test "archived documents are excluded from the default list" do
      order = order_fixture()
      {:ok, order} = Orders.transition_order(order, :sent)
      {:ok, order} = Orders.decline_quote(order, %{"decline_reason" => "other"})
      {:ok, _} = Orders.archive_order(order, "no")

      refute Enum.any?(Orders.list_orders(), &(&1.id == order.id))
      assert Enum.any?(Orders.list_orders(include_archived: true), &(&1.id == order.id))
    end
  end

  describe "quote delivery (email + token)" do
    defp send_capturing_token(order) do
      {:ok, _} =
        Orders.send_quote(order, fn t ->
          send(self(), {:token, t})
          "http://x/quote/#{t}"
        end)

      assert_received {:token, token}
      token
    end

    test "send_quote emails the customer and marks the quote sent" do
      order = order_fixture(relation_fixture(%{email: "buyer@example.com"}))
      assert {:ok, _} = Orders.send_quote(order, fn t -> "http://x/quote/#{t}" end)
      assert Orders.get_order!(order.id).status == :sent
    end

    test "send_quote needs a customer email" do
      order = order_fixture(relation_fixture(%{email: nil}))
      assert {:error, :no_email} = Orders.send_quote(order, fn t -> t end)
    end

    test "a sent quote is loadable and acceptable by its token, then consumed" do
      order = order_fixture(relation_fixture(%{email: "b@example.com"}))
      token = send_capturing_token(order)

      loaded = Orders.get_quote_by_token(token)
      assert loaded.id == order.id

      assert {:ok, accepted} = Orders.accept_quote(loaded)
      assert accepted.status == :accepted
      Orders.consume_quote_tokens(accepted)
      assert Orders.get_quote_by_token(token) == nil
    end

    test "an invalid token returns nil" do
      assert Orders.get_quote_by_token("not-a-token") == nil
    end
  end

  describe "route steps & completion" do
    setup :priced_setup

    test "steps only advance while the order is in production", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      step = hd(line.route_steps)

      assert {:error, :order_not_in_production} = Orders.advance_step(step, :in_progress)

      order = accepted_in_production(order)
      assert order.status == :in_production
      assert {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
    end

    test "illegal step transitions are rejected", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      accepted_in_production(order)
      step = Orders.get_route_step!(hd(line.route_steps).id)

      assert {:error, changeset} = Orders.advance_step(step, :done)
      assert %{status: [_]} = errors_on(changeset)
    end

    test "cannot complete until every step is done", %{template: template} do
      order = order_fixture()
      Orders.add_line_from_template(order, template.id, "100")
      order = accepted_in_production(order)

      assert {:error, :steps_unfinished} = Orders.complete_order(order, nil)
    end

    test "completing consumes the line materials' stock", %{
      template: template,
      material: material
    } do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      order = accepted_in_production(order)

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
      order = accepted_in_production(order)

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

      accepted_in_production(order)
      step = hd(line.route_steps)
      {:ok, _} = Orders.advance_step(Orders.get_route_step!(step.id), :in_progress)
      assert Orders.line_status(Orders.get_line!(line.id)) == :in_progress
    end

    test "lines can only be removed while draft", %{template: template} do
      order = order_fixture()
      {:ok, line} = Orders.add_line_from_template(order, template.id, "100")
      assert {:ok, _} = Orders.delete_line(Orders.get_line!(line.id))

      {:ok, line2} = Orders.add_line_from_template(order, template.id, "100")
      accepted_in_production(order)
      assert {:error, :not_editable} = Orders.delete_line(Orders.get_line!(line2.id))
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

      order = accepted_in_production(order)
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
      accepted_in_production(order)

      assert {:error, :not_editable} =
               Orders.set_line_dependencies(Orders.get_line!(b.id), [a.id])
    end
  end

  describe "editable window" do
    setup :priced_setup

    test "lines can still be added while accepted", %{template: template} do
      order = order_fixture()
      {:ok, order} = Orders.accept_quote(order)
      assert {:ok, _} = Orders.add_line_from_template(order, template.id, "100")
    end
  end

  describe "deliveries" do
    setup :priced_setup

    defp order_with_line(template) do
      relation = relation_fixture()
      order = order_fixture(relation)
      {:ok, line} = Orders.add_line_from_template(order, template.id, "1000")
      %{order: order, line: line, relation: relation}
    end

    defp line_allocations(order_id, line_id) do
      Orders.get_order!(order_id).deliveries
      |> Enum.flat_map(& &1.items)
      |> Enum.filter(&(&1.order_line_id == line_id))
    end

    test "two deliveries split a line equally and sum to its quantity", %{template: template} do
      %{order: order, line: line} = order_with_line(template)

      {:ok, _} = Orders.add_delivery(order, %{"street" => "A 1", "city" => "Amsterdam"})
      {:ok, _} = Orders.add_delivery(order, %{"street" => "B 2", "city" => "Rotterdam"})

      items = line_allocations(order.id, line.id)
      assert length(items) == 2
      assert Enum.all?(items, &Decimal.equal?(&1.quantity, Decimal.new("500")))

      sum = Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.quantity))
      assert Decimal.equal?(sum, Decimal.new("1000"))
    end

    test "splits into whole numbers, leftover going onto one address", %{template: template} do
      %{order: order, line: line} = order_with_line(template)

      for s <- ["A", "B", "C"], do: Orders.add_delivery(order, %{"street" => s, "city" => "X"})

      qtys = line_allocations(order.id, line.id) |> Enum.map(& &1.quantity)
      # 1000 over 3 → 334 / 333 / 333, all whole, summing to 1000
      assert Enum.all?(qtys, &(Decimal.round(&1, 0) |> Decimal.equal?(&1)))

      assert Enum.sort(Enum.map(qtys, &Decimal.to_integer(Decimal.round(&1, 0)))) == [
               333,
               333,
               334
             ]
    end

    test "removing a delivery re-divides across the rest", %{template: template} do
      %{order: order, line: line} = order_with_line(template)
      {:ok, d1} = Orders.add_delivery(order, %{"street" => "A 1", "city" => "Amsterdam"})
      {:ok, _} = Orders.add_delivery(order, %{"street" => "B 2", "city" => "Rotterdam"})

      {:ok, _} = Orders.delete_delivery(d1)
      items = line_allocations(order.id, line.id)
      assert length(items) == 1
      assert Decimal.equal?(hd(items).quantity, Decimal.new("1000"))
    end

    test "a delivery can use a saved customer address", %{template: template} do
      %{order: order, relation: relation} = order_with_line(template)

      {:ok, address} =
        CRM.create_address(relation, %{kind: :delivery, street: "Saved 9", city: "Utrecht"})

      {:ok, _} = Orders.add_delivery(order, %{"address_id" => address.id})
      delivery = Orders.get_order!(order.id).deliveries |> hd()
      assert delivery.street == "Saved 9"
      assert delivery.address_id == address.id
    end

    test "a one-off address can be saved onto the customer", %{template: template} do
      %{order: order, relation: relation} = order_with_line(template)

      {:ok, _} =
        Orders.add_delivery(order, %{
          "street" => "New 5",
          "city" => "Eindhoven",
          "save_to_customer" => "true"
        })

      assert Enum.any?(CRM.get_relation!(relation.id).addresses, &(&1.street == "New 5"))
    end

    test "a manual allocation overrides the equal split", %{template: template} do
      %{order: order, line: line} = order_with_line(template)
      {:ok, _} = Orders.add_delivery(order, %{"street" => "A 1", "city" => "Amsterdam"})
      {:ok, _} = Orders.add_delivery(order, %{"street" => "B 2", "city" => "Rotterdam"})

      item = line_allocations(order.id, line.id) |> hd()
      assert {:ok, updated} = Orders.update_delivery_item(item, "600")
      assert Decimal.equal?(updated.quantity, Decimal.new("600"))
    end

    test "deliveries cannot be added once in production", %{template: template} do
      %{order: order} = order_with_line(template)
      accepted_in_production(order)

      assert {:error, :not_editable} =
               Orders.add_delivery(order, %{"street" => "X", "city" => "Y"})
    end
  end
end
