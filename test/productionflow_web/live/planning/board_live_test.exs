defmodule ProductionflowWeb.Planning.BoardLiveTest do
  # Not async: see the note in Productionflow.PlanningTest — order creation locks
  # shared counter rows that can deadlock under concurrent suites.
  use ProductionflowWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Productionflow.ProductionFixtures
  import Productionflow.PlanningFixtures

  alias Productionflow.Planning

  defp drop(lv, params) do
    lv |> element("#planning-board") |> render_hook("drop", params)
  end

  describe "authorization (guest)" do
    test "redirects a guest to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/planning")
    end
  end

  describe "authorization" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "redirects a user without planning.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/planning")
    end
  end

  describe "viewing" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.view"]
    test "shows the backlog and machine columns but no drag handles", %{conn: conn} do
      machine = machine_fixture(%{name: "Press One"})
      _step = route_step_fixture(machine)

      {:ok, _lv, html} = live(conn, ~p"/planning")

      assert html =~ "Unscheduled"
      assert html =~ "Press One"
      assert html =~ "Line"
      refute html =~ ~s(draggable="true")
    end
  end

  describe "scheduling" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.manage"]
    test "drops a backlog step onto a machine", %{conn: conn} do
      machine = machine_fixture()
      step = route_step_fixture(machine)

      {:ok, lv, _html} = live(conn, ~p"/planning")

      drop(lv, %{
        "scheduled_id" => nil,
        "route_step_id" => to_string(step.id),
        "to_machine_id" => to_string(machine.id),
        "position" => 0
      })

      assert Planning.schedulable_steps() == []
      assert [column] = Enum.filter(Planning.board_data().columns, &(&1.machine.id == machine.id))
      assert length(column.steps) == 1
    end

    @tag permissions: ["planning.manage"]
    test "returns a scheduled step to the backlog", %{conn: conn} do
      machine = machine_fixture()
      step = route_step_fixture(machine)
      {:ok, scheduled} = Planning.schedule_step(step, machine.id)

      {:ok, lv, _html} = live(conn, ~p"/planning")

      drop(lv, %{
        "scheduled_id" => to_string(scheduled.id),
        "route_step_id" => to_string(step.id),
        "to_machine_id" => "backlog",
        "position" => 0
      })

      assert step.id in Enum.map(Planning.schedulable_steps(), & &1.id)
    end

    @tag permissions: ["planning.manage"]
    test "rejects scheduling onto the wrong machine with a flash", %{conn: conn} do
      m1 = machine_fixture()
      m2 = machine_fixture()
      step = route_step_fixture(m1)

      {:ok, lv, _html} = live(conn, ~p"/planning")

      html =
        drop(lv, %{
          "scheduled_id" => nil,
          "route_step_id" => to_string(step.id),
          "to_machine_id" => to_string(m2.id),
          "position" => 0
        })

      assert html =~ "can only run on its own machine"
      assert step.id in Enum.map(Planning.schedulable_steps(), & &1.id)
    end
  end

  describe "advancing steps" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.manage"]
    test "starts a scheduled step on an in-production order", %{conn: conn} do
      machine = machine_fixture()
      step = machine |> route_step_fixture() |> in_production!()
      {:ok, _scheduled} = Planning.schedule_step(step, machine.id)

      {:ok, lv, _html} = live(conn, ~p"/planning")

      lv
      |> element(~s|button[phx-value-route_step_id="#{step.id}"]|, "Start")
      |> render_click()

      assert Productionflow.Orders.get_route_step!(step.id).status == :in_progress
    end
  end

  describe "view-only users" do
    setup [:register_and_log_in_user]

    @tag permissions: ["planning.view"]
    test "cannot schedule via a forged drop event", %{conn: conn} do
      machine = machine_fixture()
      step = route_step_fixture(machine)

      {:ok, lv, _html} = live(conn, ~p"/planning")

      html =
        drop(lv, %{
          "scheduled_id" => nil,
          "route_step_id" => to_string(step.id),
          "to_machine_id" => to_string(machine.id),
          "position" => 0
        })

      assert html =~ "not authorized"
      assert step.id in Enum.map(Planning.schedulable_steps(), & &1.id)
    end
  end
end
