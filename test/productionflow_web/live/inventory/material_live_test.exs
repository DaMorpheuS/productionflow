defmodule ProductionflowWeb.Inventory.MaterialLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.InventoryFixtures
  import Productionflow.CRMFixtures

  alias Productionflow.Inventory

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/inventory/materials")
    end
  end

  describe "without inventory access" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/inventory/materials")
    end
  end

  describe "Index" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.view"]
    test "lists materials with low/negative badges and filters", %{conn: conn} do
      low = material_fixture(%{name: "Low ink", minimum_stock: "10"})
      _other = material_fixture(%{name: "Plenty paper"})

      {:ok, lv, _html} = live(conn, ~p"/inventory/materials")
      assert has_element?(lv, "#materials", "Low ink")
      assert has_element?(lv, "#materials", "Plenty paper")

      html = lv |> form("#material-filters", %{"search" => "low"}) |> render_change()
      assert html =~ "Low ink"
      refute html =~ "Plenty paper"
      # low-stock material shows the badge
      assert html =~ "Low"
      assert low.id
    end

    @tag permissions: ["inventory.view"]
    test "view-only users see no New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/inventory/materials")
      refute html =~ "New material"
    end

    @tag permissions: ["inventory.manage"]
    test "managers see the New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/inventory/materials")
      assert html =~ "New material"
    end
  end

  describe "Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.manage"]
    test "creates a material with supplier, category and opening stock", %{conn: conn} do
      supplier = relation_fixture(%{is_customer: false, is_supplier: true})
      category = category_fixture()
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/new")

      lv
      |> form("#material-form",
        material: %{
          name: "Vinyl",
          unit: "m²",
          supplier_id: supplier.id,
          category_id: category.id,
          opening_stock: "25"
        }
      )
      |> render_submit()

      material = Enum.find(Inventory.list_materials(), &(&1.name == "Vinyl"))
      assert material
      assert_redirect(lv, ~p"/inventory/materials/#{material}")
      material = Inventory.get_material!(material.id)
      assert Decimal.equal?(material.current_stock, 25)
      assert material.supplier_id == supplier.id
    end

    @tag permissions: ["inventory.view"]
    test "view-only users cannot reach the new form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/inventory/materials/new")
    end
  end

  describe "Show booking" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.manage", "inventory.book"]
    test "receives a purchase and updates stock + cost price", %{conn: conn} do
      material = material_fixture(%{cost_price: "1.00"})
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/#{material}")

      lv
      |> form("#booking-form", %{"kind" => "purchase", "quantity" => "40", "unit_cost" => "3.25"})
      |> render_submit()

      material = Inventory.get_material!(material.id)
      assert Decimal.equal?(material.current_stock, 40)
      assert Decimal.equal?(material.cost_price, "3.25")
      assert has_element?(lv, "#movements", "Purchase")
    end

    @tag permissions: ["inventory.book"]
    test "consumption can drive stock negative", %{conn: conn} do
      material = material_fixture()
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/#{material}")

      lv
      |> form("#booking-form", %{"kind" => "consumption", "quantity" => "5"})
      |> render_submit()

      assert Decimal.equal?(Inventory.get_material!(material.id).current_stock, -5)
    end

    @tag permissions: ["inventory.book"]
    test "adjustment set-to-current records no movement", %{conn: conn} do
      material = material_fixture(%{opening_stock: "12"})
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/#{material}")
      before = length(Inventory.get_material!(material.id).movements)

      # Switch the booking kind so the adjustment mode + fields render.
      lv |> form("#booking-form", %{"kind" => "adjustment"}) |> render_change()

      lv
      |> form("#booking-form", %{"kind" => "adjustment", "mode" => "set", "quantity" => "12"})
      |> render_submit()

      assert length(Inventory.get_material!(material.id).movements) == before
    end
  end

  describe "tri-permission matrix on Show" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.book"]
    test "book-only: booking form shown, no edit/archive, manage event denied", %{conn: conn} do
      material = material_fixture()
      {:ok, lv, html} = live(conn, ~p"/inventory/materials/#{material}")

      assert html =~ "Book stock movement"
      refute html =~ "Edit"

      render_hook(lv, "archive", %{})
      assert Inventory.get_material!(material.id).archived_at == nil
    end

    @tag permissions: ["inventory.manage"]
    test "manage-only: edit shown, booking form hidden, book event denied", %{conn: conn} do
      material = material_fixture()
      {:ok, lv, html} = live(conn, ~p"/inventory/materials/#{material}")

      assert html =~ "Edit"
      refute html =~ "Book stock movement"

      render_hook(lv, "book", %{"kind" => "purchase", "quantity" => "5"})
      assert Decimal.equal?(Inventory.get_material!(material.id).current_stock, 0)
    end
  end

  describe "Categories" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.manage"]
    test "adds and deletes a category", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/inventory/categories")

      lv |> form("#category-form", category: %{name: "Adhesives"}) |> render_submit()
      assert has_element?(lv, "#categories", "Adhesives")

      category = Enum.find(Inventory.list_categories(), &(&1.name == "Adhesives"))
      lv |> element("#categories-#{category.id} a", "Delete") |> render_click()
      refute has_element?(lv, "#categories", "Adhesives")
    end

    @tag permissions: ["inventory.view"]
    test "view-only users cannot reach categories", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/inventory/categories")
    end
  end
end
