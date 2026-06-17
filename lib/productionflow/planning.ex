defmodule Productionflow.Planning do
  @moduledoc """
  The Planning context: a production scheduling board that places order route
  steps onto machines over time.

  Each machine owns a queue of scheduled steps (`Planning.ScheduledStep`),
  ordered by `position` and packed back-to-back across the machine's working
  hours (`Production.Machine` working_day_start/end + working_days). Durations
  come from the snapshot already on each `Orders.OrderRouteStep`; the scheduler
  derives concrete `starts_at`/`ends_at` and recomputes a machine's whole queue
  whenever its membership or order changes.

  Only "active" work is scheduled: route steps that are not yet `:done`, on
  orders that are `:accepted` or `:in_production`. A step schedules onto its own
  route machine (cross-machine reassignment is out of scope for now).
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo

  alias Productionflow.Planning.{Settings, ScheduledStep}
  alias Productionflow.Production
  alias Productionflow.Production.Machine
  alias Productionflow.Orders.{Order, OrderLine, OrderRouteStep}

  @active_order_statuses [:accepted, :in_production]

  ## Settings (singleton)

  @doc "Returns the planning settings, creating the singleton row if missing."
  def get_settings do
    Repo.get(Settings, 1) || create_default_settings()
  end

  defp create_default_settings do
    %Settings{id: 1}
    |> Settings.changeset(%{})
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    Repo.get!(Settings, 1)
  end

  @doc "Returns a changeset for the settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc "Updates the planning settings."
  def update_settings(attrs) do
    get_settings()
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  The date the scheduler packs queues forward from: the configured
  `schedule_from`, never earlier than today.
  """
  def schedule_anchor_date do
    today = Date.utc_today()

    case get_settings().schedule_from do
      nil -> today
      date -> if Date.compare(date, today) == :lt, do: today, else: date
    end
  end

  ## Scheduling

  @doc "Gets a scheduled step with its route step (+ line + order) preloaded."
  def get_scheduled_step!(id) do
    ScheduledStep
    |> Repo.get!(id)
    |> Repo.preload(order_route_step: [order_line: :order])
  end

  @doc """
  Schedules a route step onto a machine, appending it to that machine's queue
  and recomputing the queue's times. The step must belong to the machine.
  """
  def schedule_step(%OrderRouteStep{} = step, machine_id) do
    machine_id = to_id(machine_id)

    cond do
      step.machine_id != machine_id ->
        {:error, :wrong_machine}

      true ->
        %ScheduledStep{}
        |> ScheduledStep.changeset(%{
          order_route_step_id: step.id,
          machine_id: machine_id,
          position: scheduled_count(machine_id)
        })
        |> Repo.insert()
        |> case do
          {:ok, scheduled_step} ->
            recompute_machine(machine_id)
            {:ok, scheduled_step}

          error ->
            error
        end
    end
  end

  @doc """
  Moves a scheduled step to `position` within `machine_id`'s queue, reseating
  the queue and recomputing times. For now a step only fits its own machine.
  """
  def move_step(%ScheduledStep{} = scheduled_step, machine_id, position) do
    machine_id = to_id(machine_id)
    scheduled_step = Repo.preload(scheduled_step, :order_route_step)

    if scheduled_step.order_route_step.machine_id != machine_id do
      {:error, :wrong_machine}
    else
      source_machine_id = scheduled_step.machine_id

      Repo.transaction(fn ->
        others =
          machine_id
          |> ordered_scheduled_steps()
          |> Enum.reject(&(&1.id == scheduled_step.id))

        others
        |> List.insert_at(position, scheduled_step)
        |> Enum.with_index()
        |> Enum.each(fn {step, index} ->
          step
          |> Ecto.Changeset.change(machine_id: machine_id, position: index)
          |> Repo.update!()
        end)
      end)

      if source_machine_id != machine_id, do: recompute_machine(source_machine_id)
      recompute_machine(machine_id)
      :ok
    end
  end

  @doc "Removes a scheduled step from its machine and recomputes that queue."
  def unschedule_step(%ScheduledStep{} = scheduled_step) do
    machine_id = scheduled_step.machine_id
    {:ok, _} = Repo.delete(scheduled_step)
    recompute_machine(machine_id)
    :ok
  end

  @doc """
  Recomputes `starts_at`/`ends_at` (and normalizes positions) for every active
  step queued on a machine, packing them back-to-back across its working hours.
  """
  def recompute_machine(machine_id) do
    machine = Production.get_machine!(machine_id)
    config = working_config(machine)
    anchor = at_time(next_working_date(schedule_anchor_date(), config), config.start)

    machine_id
    |> ordered_scheduled_steps()
    |> Enum.with_index()
    |> Enum.map_reduce(anchor, fn {scheduled_step, index}, cursor ->
      start = working_start(cursor, config)
      seconds = duration_seconds(scheduled_step.order_route_step.duration_minutes)
      finish = add_working_seconds(start, seconds, config)
      {{scheduled_step, index, start, finish}, finish}
    end)
    |> elem(0)
    |> Enum.each(fn {scheduled_step, index, start, finish} ->
      scheduled_step
      |> Ecto.Changeset.change(
        position: index,
        starts_at: to_utc(start),
        ends_at: to_utc(finish)
      )
      |> Repo.update!()
    end)

    :ok
  end

  # Active scheduled steps on a machine, ordered, with route step preloaded.
  defp ordered_scheduled_steps(machine_id) do
    from(ss in ScheduledStep,
      join: s in OrderRouteStep,
      on: s.id == ss.order_route_step_id,
      join: l in OrderLine,
      on: l.id == s.order_line_id,
      join: o in Order,
      on: o.id == l.order_id,
      where:
        ss.machine_id == ^machine_id and o.status in @active_order_statuses and
          s.status != :done,
      order_by: [asc: ss.position, asc: ss.id],
      preload: [order_route_step: s]
    )
    |> Repo.all()
  end

  defp scheduled_count(machine_id) do
    Repo.one(from ss in ScheduledStep, where: ss.machine_id == ^machine_id, select: count(ss.id))
  end

  ## Backlog & board data

  @doc """
  Route steps that can be scheduled but aren't yet: active steps (not done, on
  an accepted/in-production order) without a `ScheduledStep` row.
  """
  def schedulable_steps do
    from(s in OrderRouteStep,
      join: l in OrderLine,
      on: l.id == s.order_line_id,
      join: o in Order,
      on: o.id == l.order_id,
      left_join: ss in ScheduledStep,
      on: ss.order_route_step_id == s.id,
      where: o.status in @active_order_statuses and s.status != :done and is_nil(ss.id),
      order_by: [asc: o.id, asc: l.position, asc: s.position, asc: s.id],
      preload: [order_line: :order]
    )
    |> Repo.all()
  end

  @doc """
  Everything the board needs: a column per active machine with its scheduled
  steps, the unscheduled backlog, and the set of scheduled-step ids that sit out
  of sequence (start before an earlier step in the same line finishes).
  """
  def board_data do
    grouped = scheduled_steps_by_machine()

    columns =
      Enum.map(Production.list_machines(), fn machine ->
        %{machine: machine, steps: Map.get(grouped, machine.id, [])}
      end)

    %{
      columns: columns,
      backlog: schedulable_steps(),
      warnings: sequence_warnings(Map.values(grouped) |> List.flatten())
    }
  end

  defp scheduled_steps_by_machine do
    from(ss in ScheduledStep,
      join: s in OrderRouteStep,
      on: s.id == ss.order_route_step_id,
      join: l in OrderLine,
      on: l.id == s.order_line_id,
      join: o in Order,
      on: o.id == l.order_id,
      where: o.status in @active_order_statuses and s.status != :done,
      order_by: [asc: ss.machine_id, asc: ss.position],
      preload: [order_route_step: [order_line: :order]]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.machine_id)
  end

  @doc "Whether a scheduled step is planned to finish after its order's due date."
  def late?(%ScheduledStep{ends_at: nil}), do: false

  def late?(%ScheduledStep{ends_at: ends_at} = scheduled_step) do
    case scheduled_step.order_route_step.order_line.order.due_date do
      nil -> false
      due -> Date.compare(DateTime.to_date(ends_at), due) == :gt
    end
  end

  # Ids of scheduled steps that start before an earlier-position step in the same
  # line is planned to finish — i.e. the route order is violated by the schedule.
  defp sequence_warnings(scheduled_steps) do
    by_line = Enum.group_by(scheduled_steps, & &1.order_route_step.order_line_id)

    for {_line_id, siblings} <- by_line,
        step <- siblings,
        out_of_sequence?(step, siblings),
        into: MapSet.new(),
        do: step.id
  end

  defp out_of_sequence?(step, siblings) do
    position = step.order_route_step.position

    Enum.any?(siblings, fn other ->
      other.id != step.id and other.order_route_step.position < position and
        not is_nil(other.ends_at) and not is_nil(step.starts_at) and
        DateTime.compare(other.ends_at, step.starts_at) == :gt
    end)
  end

  ## Working-time math
  #
  # Scheduling is done in wall-clock naive datetimes and stored verbatim as UTC
  # (consistent with the app's tz-free date handling). A step's duration is laid
  # across the machine's daily working window, rolling onto the next working day
  # whenever it overflows.

  defp working_config(%Machine{} = machine) do
    %{
      start: machine.working_day_start,
      finish: machine.working_day_end,
      days: machine.working_days
    }
  end

  defp at_time(date, time), do: NaiveDateTime.new!(date, time)

  defp working_day?(date, config), do: Date.day_of_week(date) in config.days

  defp next_working_date(date, config) do
    if working_day?(date, config), do: date, else: next_working_date(Date.add(date, 1), config)
  end

  # Advances `dt` to the next valid working moment at or after it.
  defp working_start(dt, config) do
    date = NaiveDateTime.to_date(dt)
    time = NaiveDateTime.to_time(dt)

    cond do
      not working_day?(date, config) ->
        working_start(at_time(next_working_date(date, config), config.start), config)

      Time.compare(time, config.start) == :lt ->
        at_time(date, config.start)

      Time.compare(time, config.finish) != :lt ->
        working_start(at_time(Date.add(date, 1), config.start), config)

      true ->
        dt
    end
  end

  # Lays `seconds` of work from `dt` (a valid working moment) across the working
  # window, spilling onto later working days as needed.
  defp add_working_seconds(dt, seconds, config) do
    date = NaiveDateTime.to_date(dt)
    end_of_day = at_time(date, config.finish)
    left_today = NaiveDateTime.diff(end_of_day, dt)

    if seconds <= left_today do
      NaiveDateTime.add(dt, seconds)
    else
      next = working_start(at_time(Date.add(date, 1), config.start), config)
      add_working_seconds(next, seconds - left_today, config)
    end
  end

  defp duration_seconds(nil), do: 0

  defp duration_seconds(%Decimal{} = minutes) do
    minutes |> Decimal.mult(60) |> Decimal.round(0) |> Decimal.to_integer()
  end

  defp to_utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp to_id(id) when is_integer(id), do: id
  defp to_id(id) when is_binary(id), do: String.to_integer(id)
end
