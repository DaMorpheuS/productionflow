defmodule ProductionflowWeb.Orders.OrderLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CatalogFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.InventoryFixtures
  import Productionflow.CRMFixtures
  import Productionflow.OrdersFixtures

  alias Productionflow.{Orders, Inventory, Catalog}

  defp priced_template do
    template = product_template_fixture(%{name: "A5 flyer", output_unit: "flyer"})

    machine =
      machine_fixture(%{
        units_per_hour: Decimal.new(100),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(3_000),
        productive_hours_per_year: Decimal.new(1_000)
      })

    material = material_fixture(%{cost_price: Decimal.new(2), opening_stock: Decimal.new(1000)})
    route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
    template_material_fixture(template, material, %{quantity_per_unit: Decimal.new("0.5")})
    {Catalog.get_product_template!(template.id), material}
  end

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/orders")
    end
  end

  describe "without orders access" do
    setup :register_and_log_in_user

    @tag permissions: ["crm.view"]
    test "users without orders access are redirected", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/orders")
    end
  end

  describe "Index" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.view"]
    test "lists orders; view-only sees no New button", %{conn: conn} do
      order = order_fixture(relation_fixture(%{name: "Acme"}))

      {:ok, _lv, html} = live(conn, ~p"/orders")
      assert html =~ order.number
      assert html =~ "Acme"
      refute html =~ "New order"
    end

    @tag permissions: ["orders.manage"]
    test "managers see the New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/orders")
      assert html =~ "New order"
    end
  end

  describe "Form" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "creates an order with a generated number", %{conn: conn} do
      customer = relation_fixture(%{name: "Globex"})

      {:ok, lv, _html} = live(conn, ~p"/orders/new")

      lv
      |> form("#order-form", order: %{relation_id: customer.id, reference: "PO-99"})
      |> render_submit()

      order = Orders.list_orders() |> hd()
      assert order.reference == "PO-99"
      assert_redirect(lv, ~p"/orders/#{order}")
    end
  end

  describe "Settings" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "saves the numbering scheme", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/orders/settings")

      lv
      |> form("#order-settings-form",
        settings: %{number_mode: "continuous", number_prefix: "JOB"}
      )
      |> render_submit()

      settings = Orders.get_settings()
      assert settings.number_mode == :continuous
      assert settings.number_prefix == "JOB"
    end
  end

  describe "Show — production flow" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "add line, produce and complete consumes stock", %{conn: conn} do
      {template, material} = priced_template()
      order = order_fixture()

      {:ok, lv, _html} = live(conn, ~p"/orders/#{order}")

      lv
      |> form("#add-line-form", %{product_template_id: template.id, quantity: "100"})
      |> render_submit()

      assert has_element?(lv, "section", "A5 flyer")

      render_hook(lv, "transition", %{"status" => "confirmed"})
      render_hook(lv, "transition", %{"status" => "in_production"})

      # Route steps are advanced on each line's own page.
      for line <- Orders.get_order!(order.id).lines do
        {:ok, line_lv, _} = live(conn, ~p"/orders/#{order}/lines/#{line}")

        for step <- line.route_steps do
          render_hook(line_lv, "advance_step", %{"id" => step.id, "status" => "in_progress"})
          render_hook(line_lv, "advance_step", %{"id" => step.id, "status" => "done"})
        end
      end

      before = Inventory.get_material!(material.id).current_stock
      render_hook(lv, "complete", %{})

      assert Orders.get_order!(order.id).status == :completed
      after_stock = Inventory.get_material!(material.id).current_stock
      assert Decimal.equal?(Decimal.sub(before, after_stock), Decimal.new("50"))
    end

    @tag permissions: ["orders.view"]
    test "view-only users cannot drive transitions (server-guarded)", %{conn: conn} do
      order = order_fixture()

      {:ok, lv, html} = live(conn, ~p"/orders/#{order}")
      refute html =~ "Confirm"

      render_hook(lv, "transition", %{"status" => "confirmed"})
      assert Orders.get_order!(order.id).status == :draft
    end
  end

  describe "Show — custom (ad-hoc) lines" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "adds a custom line with a manual price and its own machine step", %{conn: conn} do
      {_template, _material} = priced_template()
      machine = Productionflow.Production.list_machines() |> hd()
      order = order_fixture()

      {:ok, lv, _html} = live(conn, ~p"/orders/#{order}")

      lv
      |> form("#add-custom-line-form", %{
        description: "Custom box",
        output_unit: "box",
        quantity: "10",
        unit_price: "25"
      })
      |> render_submit()

      assert has_element?(lv, "section", "Custom box")
      line = Orders.get_order!(order.id).lines |> hd()
      assert line.price_source == :manual

      # The line opens on its own page where its route is built.
      {:ok, line_lv, _} = live(conn, ~p"/orders/#{order}/lines/#{line}")

      line_lv
      |> form("#add-step-form", %{machine_id: machine.id, machine_quantity: "100"})
      |> render_submit()

      assert length(Orders.get_line!(line.id).route_steps) == 1
    end
  end

  describe "Show — deliveries" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "adds delivery addresses and auto-splits a line", %{conn: conn} do
      {template, _material} = priced_template()
      order = order_fixture()

      {:ok, lv, _html} = live(conn, ~p"/orders/#{order}")

      lv
      |> form("#add-line-form", %{product_template_id: template.id, quantity: "1000"})
      |> render_submit()

      lv |> form("#add-delivery-form", %{street: "A 1", city: "Amsterdam"}) |> render_submit()
      assert has_element?(lv, "section", "Amsterdam")

      lv |> form("#add-delivery-form", %{street: "B 2", city: "Rotterdam"}) |> render_submit()

      order = Orders.get_order!(order.id)
      line = hd(order.lines)

      qtys =
        order.deliveries
        |> Enum.flat_map(& &1.items)
        |> Enum.filter(&(&1.order_line_id == line.id))
        |> Enum.map(& &1.quantity)

      assert length(qtys) == 2
      assert Enum.all?(qtys, &Decimal.equal?(&1, Decimal.new("500")))
    end
  end

  describe "Line page" do
    setup :register_and_log_in_user

    @tag permissions: ["orders.manage"]
    test "a line is listed as a link, opens on its own page, and can be removed", %{conn: conn} do
      {template, _material} = priced_template()
      order = order_fixture()

      {:ok, lv, _html} = live(conn, ~p"/orders/#{order}")

      lv
      |> form("#add-line-form", %{product_template_id: template.id, quantity: "100"})
      |> render_submit()

      line = Orders.get_order!(order.id).lines |> hd()
      assert has_element?(lv, "a[href='/orders/#{order.id}/lines/#{line.id}']")

      {:ok, line_lv, html} = live(conn, ~p"/orders/#{order}/lines/#{line}")
      assert html =~ "Route"
      assert html =~ "A5 flyer"

      line_lv |> element("button", "Remove line") |> render_click()
      assert_redirect(line_lv, ~p"/orders/#{order}")
      assert Orders.get_order!(order.id).lines == []
    end

    @tag permissions: ["orders.manage"]
    test "a dependent line is ordered below and indented under its dependency", %{conn: conn} do
      order = order_fixture()

      {:ok, lv, _html} = live(conn, ~p"/orders/#{order}")

      # Add the dependent ("Child") first, then its dependency ("Parent").
      lv
      |> form("#add-custom-line-form", %{description: "Child", quantity: "1"})
      |> render_submit()

      lv
      |> form("#add-custom-line-form", %{description: "Parent", quantity: "1"})
      |> render_submit()

      lines = Orders.get_order!(order.id).lines
      child = Enum.find(lines, &(&1.description == "Child"))
      parent = Enum.find(lines, &(&1.description == "Parent"))
      {:ok, _} = Orders.set_line_dependencies(Orders.get_line!(child.id), [parent.id])

      {:ok, _lv, html} = live(conn, ~p"/orders/#{order}")
      assert html =~ "waits for Parent"
      # Parent is rendered above Child even though it was added after.
      assert elem(:binary.match(html, "Parent"), 0) < elem(:binary.match(html, "Child"), 0)
    end
  end
end
