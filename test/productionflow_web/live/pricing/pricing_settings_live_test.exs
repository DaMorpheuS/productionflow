defmodule ProductionflowWeb.Pricing.PricingSettingsLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Productionflow.Pricing

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/pricing/settings")
    end
  end

  describe "without manage access" do
    setup [:register_and_log_in_user]

    @tag permissions: ["pricing.view"]
    test "view-only users cannot reach settings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pricing/settings")
    end
  end

  describe "Edit" do
    setup [:register_and_log_in_user]

    @tag permissions: ["pricing.manage"]
    test "saves the default margin", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pricing/settings")

      lv
      |> form("#pricing-settings-form", settings: %{default_margin_pct: "42"})
      |> render_submit()

      assert Decimal.equal?(Pricing.get_settings().default_margin_pct, Decimal.new("42"))
    end
  end
end
