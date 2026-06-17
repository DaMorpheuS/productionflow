defmodule Productionflow.PlanningTest do
  # Not async: these tests create many orders, which lock the shared
  # order-number counter rows; running them concurrently with the other
  # order-creating suites can deadlock on those locks.
  use Productionflow.DataCase, async: false

  alias Productionflow.Planning
  alias Productionflow.Planning.ScheduledStep
  alias Productionflow.Orders

  import Productionflow.ProductionFixtures
  import Productionflow.OrdersFixtures
  import Productionflow.PlanningFixtures

  # Pin the schedule anchor to a fixed Monday in the future so derived datetimes
  # are deterministic (the anchor is never clamped up to "today").
  setup do
    monday =
      ~D[2027-01-01]
      |> Stream.iterate(&Date.add(&1, 1))
      |> Enum.find(&(Date.day_of_week(&1) == 1))

    {:ok, _} = Planning.update_settings(%{schedule_from: monday})
    %{monday: monday}
  end

  defp utc(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  defp reload(scheduled_step), do: Planning.get_scheduled_step!(scheduled_step.id)

  defp step_ids(steps), do: Enum.map(steps, & &1.id)

  describe "settings" do
    test "schedule_anchor_date never precedes today" do
      {:ok, _} = Planning.update_settings(%{schedule_from: ~D[2000-01-01]})
      assert Planning.schedule_anchor_date() == Date.utc_today()
    end
  end

  describe "recompute_machine/1" do
    test "packs steps back-to-back from the anchor at the working-day start", %{monday: monday} do
      machine = machine_fixture()
      s1 = route_step_fixture(machine, machine_quantity: 60)
      s2 = route_step_fixture(machine, machine_quantity: 30)

      {:ok, ss1} = Planning.schedule_step(s1, machine.id)
      {:ok, ss2} = Planning.schedule_step(s2, machine.id)

      ss1 = reload(ss1)
      ss2 = reload(ss2)

      assert ss1.starts_at == utc(monday, ~T[08:00:00])
      assert ss1.ends_at == utc(monday, ~T[09:00:00])
      assert ss2.starts_at == utc(monday, ~T[09:00:00])
      assert ss2.ends_at == utc(monday, ~T[09:30:00])
    end

    test "rolls a step that overflows the day onto the next working day", %{monday: monday} do
      machine = machine_fixture()
      # 600 minutes; an 08:00–16:30 day is 510 working minutes, leaving 90.
      step = route_step_fixture(machine, machine_quantity: 600)

      {:ok, ss} = Planning.schedule_step(step, machine.id)
      ss = reload(ss)

      assert ss.starts_at == utc(monday, ~T[08:00:00])
      assert ss.ends_at == utc(Date.add(monday, 1), ~T[09:30:00])
    end

    test "skips non-working days when rolling over", %{monday: monday} do
      machine = machine_fixture(%{working_days: [1, 3]})
      step = route_step_fixture(machine, machine_quantity: 600)

      {:ok, ss} = Planning.schedule_step(step, machine.id)
      ss = reload(ss)

      # 90 minutes spill from Monday past the skipped Tuesday onto Wednesday.
      assert ss.ends_at == utc(Date.add(monday, 2), ~T[09:30:00])
    end
  end

  describe "schedule_step/2" do
    test "rejects a step that does not belong to the machine" do
      m1 = machine_fixture()
      m2 = machine_fixture()
      step = route_step_fixture(m1)

      assert {:error, :wrong_machine} = Planning.schedule_step(step, m2.id)
    end

    test "cannot schedule the same step twice" do
      machine = machine_fixture()
      step = route_step_fixture(machine)

      {:ok, _} = Planning.schedule_step(step, machine.id)
      assert {:error, changeset} = Planning.schedule_step(step, machine.id)
      assert errors_on(changeset)[:order_route_step_id]
    end
  end

  describe "move_step/3" do
    test "reorders the queue and recomputes times", %{monday: monday} do
      machine = machine_fixture()
      [a, b, c] = for _ <- 1..3, do: route_step_fixture(machine, machine_quantity: 60)

      {:ok, sa} = Planning.schedule_step(a, machine.id)
      {:ok, sb} = Planning.schedule_step(b, machine.id)
      {:ok, sc} = Planning.schedule_step(c, machine.id)

      :ok = Planning.move_step(reload(sc), machine.id, 0)

      assert reload(sc).position == 0
      assert reload(sc).starts_at == utc(monday, ~T[08:00:00])
      assert reload(sa).position == 1
      assert reload(sa).starts_at == utc(monday, ~T[09:00:00])
      assert reload(sb).position == 2
    end
  end

  describe "unschedule_step/1" do
    test "removes the step, recomputes the rest, and returns it to the backlog", %{monday: monday} do
      machine = machine_fixture()
      a = route_step_fixture(machine, machine_quantity: 60)
      b = route_step_fixture(machine, machine_quantity: 60)

      {:ok, sa} = Planning.schedule_step(a, machine.id)
      {:ok, sb} = Planning.schedule_step(b, machine.id)

      :ok = Planning.unschedule_step(reload(sa))

      assert Repo.get(ScheduledStep, sa.id) == nil
      assert reload(sb).position == 0
      assert reload(sb).starts_at == utc(monday, ~T[08:00:00])
      assert a.id in step_ids(Planning.schedulable_steps())
    end
  end

  describe "schedulable_steps/0" do
    test "lists active, unscheduled steps and excludes scheduled ones" do
      machine = machine_fixture()
      s1 = route_step_fixture(machine)
      s2 = route_step_fixture(machine)

      ids = step_ids(Planning.schedulable_steps())
      assert s1.id in ids
      assert s2.id in ids

      {:ok, _} = Planning.schedule_step(s1, machine.id)

      ids = step_ids(Planning.schedulable_steps())
      refute s1.id in ids
      assert s2.id in ids
    end

    test "excludes steps of orders that are not yet accepted" do
      machine = machine_fixture()
      order = order_fixture()
      {:ok, line} = Orders.add_blank_line(order, %{"description" => "L", "quantity" => "1"})

      {:ok, _} =
        Orders.add_line_route_step(line, %{
          "machine_id" => machine.id,
          "machine_quantity" => "60"
        })

      step = Orders.get_line!(line.id).route_steps |> List.last()
      refute step.id in step_ids(Planning.schedulable_steps())
    end
  end

  describe "late?/1" do
    test "is true when the step finishes after the order's due date", %{monday: monday} do
      machine = machine_fixture()
      late = route_step_fixture(machine, machine_quantity: 60, due_date: Date.add(monday, -1))
      ontime = route_step_fixture(machine, machine_quantity: 60, due_date: Date.add(monday, 3))

      {:ok, late_ss} = Planning.schedule_step(late, machine.id)
      {:ok, ontime_ss} = Planning.schedule_step(ontime, machine.id)

      assert Planning.late?(reload(late_ss))
      refute Planning.late?(reload(ontime_ss))
    end
  end

  describe "board_data/0 sequence warnings" do
    test "flags a step scheduled before an earlier step in the same line" do
      machine = machine_fixture()
      order = order_fixture()
      {:ok, line} = Orders.add_blank_line(order, %{"description" => "L", "quantity" => "1"})

      for _ <- 1..2 do
        {:ok, _} =
          Orders.add_line_route_step(line, %{
            "machine_id" => machine.id,
            "machine_quantity" => "60"
          })
      end

      {:ok, _} = Orders.accept_quote(order)
      [step1, step2] = Orders.get_line!(line.id).route_steps

      # Schedule the second route step first, so it runs before the first one.
      {:ok, ss2} = Planning.schedule_step(step2, machine.id)
      {:ok, _ss1} = Planning.schedule_step(step1, machine.id)

      assert MapSet.member?(Planning.board_data().warnings, ss2.id)

      # Reordering them into route order clears the warning.
      :ok = Planning.move_step(reload(ss2), machine.id, 1)
      refute MapSet.member?(Planning.board_data().warnings, ss2.id)
    end
  end

  describe "board_data/0" do
    test "returns a column per machine with its scheduled steps and the backlog" do
      machine = machine_fixture()
      scheduled = route_step_fixture(machine)
      _backlog = route_step_fixture(machine)

      {:ok, ss} = Planning.schedule_step(scheduled, machine.id)

      %{columns: columns, backlog: backlog} = Planning.board_data()
      column = Enum.find(columns, &(&1.machine.id == machine.id))

      assert Enum.map(column.steps, & &1.id) == [ss.id]
      assert scheduled.id not in step_ids(backlog)
      assert length(backlog) == 1
    end
  end
end
