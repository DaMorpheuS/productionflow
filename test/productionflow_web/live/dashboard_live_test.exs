defmodule ProductionflowWeb.DashboardLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
  end
end
