defmodule ProductionflowWeb.Planning.SettingsLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Productionflow.Planning

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/planning/settings")
    end
  end

  describe "without manage access" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.view"]
    test "view-only users cannot reach settings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/planning/settings")
    end
  end

  describe "Edit" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.manage"]
    test "saves the schedule-from date", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/planning/settings")

      lv
      |> form("#planning-settings-form", settings: %{schedule_from: "2026-07-01"})
      |> render_submit()

      assert Planning.get_settings().schedule_from == ~D[2026-07-01]
    end
  end
end
