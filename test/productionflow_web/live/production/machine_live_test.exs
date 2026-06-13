defmodule ProductionflowWeb.Production.MachineLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.ProductionFixtures
  import Productionflow.AccountsFixtures

  alias Productionflow.Production

  defp operator_with_cost(cost) do
    user = user_fixture()
    Productionflow.Repo.update!(Ecto.Changeset.change(user, hourly_cost: Decimal.new(cost)))
  end

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/production/machines")
    end
  end

  describe "without production.view permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/production/machines")
    end
  end

  describe "Index" do
    setup [:register_and_log_in_user]

    @tag permissions: ["production.view"]
    test "lists machines and filters", %{conn: conn} do
      laser = machine_fixture(%{name: "Laser cutter"})
      _press = machine_fixture(%{name: "Offset press"})

      {:ok, lv, _html} = live(conn, ~p"/production/machines")
      assert has_element?(lv, "#machines", "Laser cutter")
      assert has_element?(lv, "#machines", "Offset press")

      lv |> form("#machine-filters", %{"search" => "laser"}) |> render_change()
      assert has_element?(lv, "#machines", "Laser cutter")
      refute has_element?(lv, "#machines", "Offset press")
      assert laser.id
    end

    @tag permissions: ["production.view"]
    test "view-only users see no New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/production/machines")
      refute html =~ "New machine"
    end

    @tag permissions: ["production.manage"]
    test "managers see the New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/production/machines")
      assert html =~ "New machine"
    end
  end

  describe "Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["production.view"]
    test "view-only users cannot reach the new form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/production/machines/new")
    end

    @tag permissions: ["production.manage"]
    test "creates a machine and assigns an operator", %{conn: conn} do
      operator = operator_with_cost("30")
      {:ok, lv, _html} = live(conn, ~p"/production/machines/new")

      lv
      |> form("#machine-form",
        machine: %{
          name: "Plotter",
          output_unit: "m",
          units_per_hour: "120",
          operator_ids: ["", to_string(operator.id)]
        }
      )
      |> render_submit()

      machine = Enum.find(Production.list_machines(), &(&1.name == "Plotter"))
      assert machine
      assert_redirect(lv, ~p"/production/machines/#{machine}")
      assert Enum.map(Production.get_machine!(machine.id).operators, & &1.id) == [operator.id]
    end

    @tag permissions: ["production.manage"]
    test "shows a live machine cost preview", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/production/machines/new")

      html =
        lv
        |> form("#machine-form",
          machine: %{
            name: "M",
            output_unit: "pieces",
            units_per_hour: "60",
            purchase_price: "10000",
            lifetime_years: "5",
            yearly_maintenance_cost: "2000",
            productive_hours_per_year: "1000"
          }
        )
        |> render_change()

      # (10000/5 + 2000) / 1000 = 4.00 per hour
      assert html =~ "€4.00"
    end

    @tag permissions: ["production.manage"]
    test "requires name, output_unit and units_per_hour", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/production/machines/new")

      html = lv |> form("#machine-form", machine: %{name: ""}) |> render_submit()
      assert html =~ "can&#39;t be blank"
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user]

    @tag permissions: ["production.manage"]
    test "adds and deletes a time modifier", %{conn: conn} do
      machine = machine_fixture()
      {:ok, lv, _html} = live(conn, ~p"/production/machines/#{machine}")

      lv
      |> form("#modifier-form",
        modifier: %{name: "Complex shape", kind: "percentage", value: "20"}
      )
      |> render_submit()

      assert has_element?(lv, "#time-modifiers", "Complex shape")

      [modifier] = Production.get_machine!(machine.id).time_modifiers
      lv |> element("#time-modifiers a", "Delete") |> render_click()
      refute has_element?(lv, "#time-modifiers", "Complex shape")
      assert Production.get_machine!(machine.id).time_modifiers == []
      assert modifier.id
    end

    @tag permissions: ["production.view"]
    test "estimates duration for a quantity", %{conn: conn} do
      machine = machine_fixture(%{units_per_hour: Decimal.new(60), setup_minutes: Decimal.new(0)})
      {:ok, lv, _html} = live(conn, ~p"/production/machines/#{machine}")

      html = lv |> form("#estimate-form", %{"quantity" => "60"}) |> render_change()
      assert html =~ "1h"
    end

    @tag permissions: ["production.view"]
    test "view-only users cannot add modifiers (server-guarded)", %{conn: conn} do
      machine = machine_fixture()
      {:ok, lv, html} = live(conn, ~p"/production/machines/#{machine}")
      refute html =~ "Add"

      render_hook(lv, "add_modifier", %{
        "modifier" => %{"name" => "X", "kind" => "percentage", "value" => "5"}
      })

      assert Production.get_machine!(machine.id).time_modifiers == []
    end

    @tag permissions: ["production.manage"]
    test "archives and unarchives", %{conn: conn} do
      machine = machine_fixture()
      {:ok, lv, _html} = live(conn, ~p"/production/machines/#{machine}")

      lv |> element("button", "Archive") |> render_click()
      assert Production.get_machine!(machine.id).archived_at

      lv |> element("button", "Unarchive") |> render_click()
      refute Production.get_machine!(machine.id).archived_at
    end
  end

  describe "Settings" do
    setup [:register_and_log_in_user]

    @tag permissions: ["production.manage"]
    test "updates the energy price", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/production/settings")

      lv
      |> form("#settings-form", settings: %{energy_price_per_kwh: "0.35"})
      |> render_submit()

      assert Decimal.equal?(Production.get_settings().energy_price_per_kwh, Decimal.new("0.35"))
    end

    @tag permissions: ["production.view"]
    test "view-only users cannot reach settings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/production/settings")
    end
  end
end
