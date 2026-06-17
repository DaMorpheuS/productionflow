defmodule ProductionflowWeb.DashboardLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.OrdersFixtures

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
    end
  end

  describe "as an authenticated user" do
    setup [:register_and_log_in_user]

    test "renders the dashboard", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Welcome back"
      assert html =~ user.email
    end

    @tag permissions: ["orders.view"]
    test "shows order KPIs and recent activity", %{conn: conn} do
      order = order_fixture()

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Open quotes"
      assert html =~ "Recent activity"
      assert html =~ order.quote_number
    end

    @tag permissions: []
    test "shows an empty dashboard without data permissions", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Needs attention"
      assert html =~ "Nothing needs attention"
    end
  end
end
