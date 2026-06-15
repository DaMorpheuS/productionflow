defmodule ProductionflowWeb.Catalog.ProductTemplateLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CatalogFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.InventoryFixtures

  alias Productionflow.Catalog

  defp complete_machine do
    machine_fixture(%{
      name: "Digital press",
      units_per_hour: Decimal.new(60),
      purchase_price: Decimal.new(10_000),
      lifetime_years: Decimal.new(5),
      yearly_maintenance_cost: Decimal.new(2_000),
      productive_hours_per_year: Decimal.new(1_000)
    })
  end

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/catalog/products")
    end
  end

  describe "without catalog access" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/catalog/products")
    end
  end

  describe "Index" do
    setup [:register_and_log_in_user]

    @tag permissions: ["catalog.view"]
    test "lists and filters templates", %{conn: conn} do
      a = product_template_fixture(%{name: "A5 flyer"})
      _b = product_template_fixture(%{name: "Roll banner"})

      {:ok, lv, _html} = live(conn, ~p"/catalog/products")
      assert has_element?(lv, "#templates", "A5 flyer")

      html = lv |> form("#product-filters", %{"search" => "flyer"}) |> render_change()
      assert html =~ "A5 flyer"
      refute html =~ "Roll banner"
      assert a.id
    end

    @tag permissions: ["catalog.view"]
    test "view-only users see no New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/catalog/products")
      refute html =~ "New product"
    end

    @tag permissions: ["catalog.manage"]
    test "managers see the New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/catalog/products")
      assert html =~ "New product"
    end
  end

  describe "Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["catalog.manage"]
    test "creates a product", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/catalog/products/new")

      lv
      |> form("#product-form", product_template: %{name: "A5 flyer 4/4", output_unit: "flyer"})
      |> render_submit()

      template = Enum.find(Catalog.list_product_templates(), &(&1.name == "A5 flyer 4/4"))
      assert template
      assert_redirect(lv, ~p"/catalog/products/#{template}")
    end

    @tag permissions: ["catalog.view"]
    test "view-only users cannot reach the new form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/catalog/products/new")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user]

    @tag permissions: ["catalog.manage"]
    test "adds a route step and shows it", %{conn: conn} do
      template = product_template_fixture()
      machine = complete_machine()
      {:ok, lv, _html} = live(conn, ~p"/catalog/products/#{template}/steps/new")

      lv
      |> form("#route-step-form", route_step: %{machine_id: machine.id, quantity_per_unit: "1"})
      |> render_submit()

      {:ok, lv, _html} = live(conn, ~p"/catalog/products/#{template}")
      assert has_element?(lv, "#route-steps", "Digital press")
    end

    @tag permissions: ["catalog.manage"]
    test "renders a cost & time preview", %{conn: conn} do
      template = product_template_fixture(%{output_unit: "flyer"})
      machine = complete_machine()
      material = material_fixture(%{cost_price: Decimal.new(2)})
      route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
      template_material_fixture(template, material, %{quantity_per_unit: Decimal.new("0.25")})

      {:ok, lv, _html} = live(conn, ~p"/catalog/products/#{template}")

      html = lv |> form("#estimate-form", %{"quantity" => "60"}) |> render_change()
      # 60 flyers / 60 per hour = 1h
      assert html =~ "1h"
      # machine cost €4.00, material €30.00, total €34.00
      assert html =~ "€4.00"
      assert html =~ "€34.00"
    end

    @tag permissions: ["catalog.manage"]
    test "deletes a route step", %{conn: conn} do
      template = product_template_fixture()
      machine = complete_machine()
      step = route_step_fixture(template, machine)

      {:ok, lv, _html} = live(conn, ~p"/catalog/products/#{template}")
      lv |> element("#route-steps a", "Delete") |> render_click()

      assert Catalog.get_product_template!(template.id).route_steps == []
      assert step.id
    end

    @tag permissions: ["catalog.view"]
    test "view-only users cannot mutate (server-guarded)", %{conn: conn} do
      template = product_template_fixture()
      machine = complete_machine()
      step = route_step_fixture(template, machine)

      {:ok, lv, html} = live(conn, ~p"/catalog/products/#{template}")
      refute html =~ "Add step"

      render_hook(lv, "delete_step", %{"id" => step.id})
      assert length(Catalog.get_product_template!(template.id).route_steps) == 1
    end
  end

  describe "RouteStep form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["catalog.manage"]
    test "reveals the machine's time modifiers when a machine is chosen", %{conn: conn} do
      template = product_template_fixture()
      machine = complete_machine()

      time_modifier_fixture(machine, %{
        name: "Complex shape",
        kind: :percentage,
        value: Decimal.new(20)
      })

      {:ok, lv, html} = live(conn, ~p"/catalog/products/#{template}/steps/new")
      refute html =~ "Complex shape"

      html =
        lv
        |> form("#route-step-form", route_step: %{machine_id: machine.id, quantity_per_unit: "1"})
        |> render_change()

      assert html =~ "Complex shape"
    end
  end
end
