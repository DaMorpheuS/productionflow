defmodule ProductionflowWeb.SearchLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CRMFixtures
  import Productionflow.OrdersFixtures
  import Productionflow.CatalogFixtures

  describe "authorization" do
    test "redirects a guest to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/search")
    end
  end

  describe "searching" do
    setup [:register_and_log_in_user]

    @tag permissions: ["orders.view", "crm.view"]
    test "finds matching orders and relations across groups", %{conn: conn} do
      relation = relation_fixture(%{name: "Zephyr Printing"})
      order = order_fixture(relation)

      {:ok, _lv, html} = live(conn, ~p"/search?q=Zephyr")

      assert html =~ "Relations"
      assert html =~ "Zephyr Printing"
      assert html =~ "Orders &amp; quotes"
      assert html =~ order.quote_number
    end

    @tag permissions: ["catalog.view"]
    test "searches as you type", %{conn: conn} do
      product_template_fixture(%{name: "Glow Poster A1"})

      {:ok, lv, _html} = live(conn, ~p"/search")

      html = lv |> form("#search-form", %{q: "Glow"}) |> render_change()

      assert html =~ "Products"
      assert html =~ "Glow Poster A1"
    end

    @tag permissions: ["crm.view"]
    test "hides areas the user cannot view", %{conn: conn} do
      relation = relation_fixture(%{name: "Zephyr Printing"})
      _order = order_fixture(relation)

      {:ok, _lv, html} = live(conn, ~p"/search?q=Zephyr")

      assert html =~ "Zephyr Printing"
      refute html =~ "Orders &"
    end

    @tag permissions: ["crm.view"]
    test "prompts when the query is empty", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/search")
      assert html =~ "Type above to search"
    end

    @tag permissions: ["crm.view"]
    test "reports when nothing matches", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/search?q=nothingmatchesthis")
      assert html =~ "No matches"
    end
  end
end
