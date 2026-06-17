defmodule ProductionflowWeb.Planning.BoardLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Planning, Orders}
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Planning board"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "planning.manage"))
     |> assign(:anchor, Planning.schedule_anchor_date())
     |> load_board()}
  end

  defp load_board(socket) do
    %{columns: columns, backlog: backlog, warnings: warnings} = Planning.board_data()

    socket
    |> assign(:columns, Enum.map(columns, &present_column(&1, warnings)))
    |> assign(:backlog, Enum.map(backlog, &present_backlog/1))
  end

  defp present_column(%{machine: machine, steps: steps}, warnings) do
    %{machine: machine, cards: Enum.map(steps, &present_scheduled(&1, warnings))}
  end

  defp present_scheduled(scheduled_step, warnings) do
    step = scheduled_step.order_route_step
    line = step.order_line

    base(step, line)
    |> Map.merge(%{
      dom_id: "scheduled-#{scheduled_step.id}",
      scheduled_id: scheduled_step.id,
      starts_at: scheduled_step.starts_at,
      ends_at: scheduled_step.ends_at,
      late: Planning.late?(scheduled_step),
      warn: MapSet.member?(warnings, scheduled_step.id)
    })
  end

  defp present_backlog(step) do
    base(step, step.order_line)
    |> Map.merge(%{
      dom_id: "backlog-#{step.id}",
      scheduled_id: nil,
      starts_at: nil,
      ends_at: nil,
      late: false,
      warn: false
    })
  end

  defp base(step, line) do
    order = line.order

    %{
      route_step_id: step.id,
      machine_id: step.machine_id,
      machine_name: step.machine_name,
      order_label: order.number || order.quote_number,
      order_status: order.status,
      description: line.description,
      quantity: step.machine_quantity,
      duration_minutes: step.duration_minutes,
      step_status: step.status
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Planning board")}
        <:subtitle>
          {gettext("Scheduling from %{date}.", date: Calendar.strftime(@anchor, "%d %b %Y"))}
          <span :if={@can_manage}>{gettext("Drag steps onto a machine to schedule them.")}</span>
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/planning/settings"}>{gettext("Settings")}</.button>
        </:actions>
      </.header>

      <div id="planning-board" phx-hook="BoardDnD" class="flex gap-4 overflow-x-auto pb-4">
        <section
          data-dropzone
          data-machine-id="backlog"
          class="flex w-64 shrink-0 flex-col rounded-xl border border-base-300 bg-base-200/40 p-3"
        >
          <h2 class="mb-1 text-sm font-semibold">{gettext("Unscheduled")}</h2>
          <p class="mb-2 text-xs text-base-content/50">
            {gettext("%{count} step(s)", count: length(@backlog))}
          </p>
          <ul class="flex flex-1 flex-col gap-2">
            <li
              :if={@backlog == []}
              class="rounded-lg border border-dashed border-base-300 p-3 text-center text-xs text-base-content/50"
            >
              {gettext("Nothing waiting.")}
            </li>
            <.card :for={card <- @backlog} card={card} can_manage={@can_manage} />
          </ul>
        </section>

        <section
          :for={column <- @columns}
          data-dropzone
          data-machine-id={column.machine.id}
          class="flex w-64 shrink-0 flex-col rounded-xl border border-base-300 bg-base-100 p-3"
        >
          <h2 class="text-sm font-semibold">{column.machine.name}</h2>
          <p class="mb-2 text-xs text-base-content/50">
            {working_hours(column.machine)}
          </p>
          <ul class="flex flex-1 flex-col gap-2">
            <li
              :if={column.cards == []}
              class="rounded-lg border border-dashed border-base-300 p-3 text-center text-xs text-base-content/50"
            >
              {gettext("Drop a step here.")}
            </li>
            <.card :for={card <- column.cards} card={card} can_manage={@can_manage} />
          </ul>
        </section>

        <p
          :if={@columns == []}
          class="self-center text-sm text-base-content/60"
        >
          {gettext("No machines yet. Add one under Machines first.")}
        </p>
      </div>
    </Layouts.app>
    """
  end

  attr :card, :map, required: true
  attr :can_manage, :boolean, required: true

  defp card(assigns) do
    ~H"""
    <li
      id={@card.dom_id}
      data-draggable={@can_manage && "true"}
      draggable={@can_manage && "true"}
      data-route-step-id={@card.route_step_id}
      data-machine-id={@card.machine_id}
      data-scheduled-id={@card.scheduled_id}
      title={time_range(@card)}
      class={[
        "rounded-lg border bg-base-100 p-2 text-sm shadow-sm",
        @can_manage && "cursor-grab active:cursor-grabbing",
        @card.late && "border-error/60",
        !@card.late && "border-base-300"
      ]}
    >
      <div class="flex items-center justify-between gap-2">
        <span class="font-medium">{@card.order_label}</span>
        <span class="flex items-center gap-1">
          <span :if={@card.late} class="badge badge-error badge-xs">{gettext("late")}</span>
          <span :if={@card.warn} class="badge badge-warning badge-xs">{gettext("order")}</span>
          <span class={["badge badge-xs", status_class(@card.step_status)]}>
            {Phoenix.Naming.humanize(@card.step_status)}
          </span>
        </span>
      </div>

      <p class="truncate text-xs text-base-content/70">{@card.description}</p>

      <div class="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-base-content/60">
        <span>{@card.machine_name}</span>
        <span>· {qty(@card.quantity)}</span>
        <span>· {duration(@card.duration_minutes)}</span>
      </div>

      <p :if={@card.starts_at} class="mt-1 text-xs text-base-content/60">
        {when_label(@card.starts_at)}
      </p>

      <div
        :if={@can_manage and not is_nil(@card.scheduled_id) and step_actions(@card) != []}
        class="mt-2 flex gap-1"
      >
        <.button
          :for={{label, to} <- step_actions(@card)}
          phx-click="advance"
          phx-value-route_step_id={@card.route_step_id}
          phx-value-to={to}
          class="btn-xs"
        >
          {label}
        </.button>
      </div>
    </li>
    """
  end

  ## Events

  @impl true
  def handle_event("drop", params, socket) do
    guard_manage(socket, fn ->
      case apply_drop(params) do
        :ok ->
          {:noreply, load_board(socket)}

        {:error, reason} ->
          {:noreply, socket |> put_flash(:error, drop_error(reason)) |> load_board()}
      end
    end)
  end

  def handle_event("advance", %{"route_step_id" => id, "to" => to}, socket) do
    guard_manage(socket, fn ->
      status = String.to_existing_atom(to)

      case Orders.advance_step(Orders.get_route_step!(id), status) do
        {:ok, _step} ->
          {:noreply, load_board(socket)}

        {:error, reason} ->
          {:noreply, socket |> put_flash(:error, advance_error(reason)) |> load_board()}
      end
    end)
  end

  defp apply_drop(%{"to_machine_id" => "backlog", "scheduled_id" => sid}) when not is_nil(sid) do
    Planning.unschedule_step(Planning.get_scheduled_step!(sid))
  end

  defp apply_drop(%{"scheduled_id" => sid} = params) when not is_nil(sid) do
    Planning.move_step(
      Planning.get_scheduled_step!(sid),
      String.to_integer(params["to_machine_id"]),
      params["position"] || 0
    )
  end

  defp apply_drop(%{"route_step_id" => rid, "to_machine_id" => mid} = params)
       when not is_nil(rid) do
    machine_id = String.to_integer(mid)

    with {:ok, scheduled_step} <-
           Planning.schedule_step(Orders.get_route_step!(rid), machine_id) do
      case params["position"] do
        nil -> :ok
        position -> Planning.move_step(scheduled_step, machine_id, position)
      end
    end
  end

  defp apply_drop(_params), do: :ok

  defp guard_manage(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  ## Display helpers

  # Buttons to advance a step, only while its order is in production.
  defp step_actions(%{order_status: :in_production, step_status: :pending}),
    do: [{gettext("Start"), "in_progress"}]

  defp step_actions(%{order_status: :in_production, step_status: :in_progress}),
    do: [{gettext("Done"), "done"}]

  defp step_actions(_card), do: []

  defp status_class(:pending), do: "badge-ghost"
  defp status_class(:in_progress), do: "badge-info"
  defp status_class(:done), do: "badge-success"

  defp working_hours(machine) do
    days =
      machine.working_days
      |> Enum.sort()
      |> Enum.map_join("", &weekday_initial/1)

    "#{Calendar.strftime(machine.working_day_start, "%H:%M")}–" <>
      "#{Calendar.strftime(machine.working_day_end, "%H:%M")} · #{days}"
  end

  @weekday_initials %{1 => "M", 2 => "T", 3 => "W", 4 => "T", 5 => "F", 6 => "S", 7 => "S"}
  defp weekday_initial(day), do: Map.fetch!(@weekday_initials, day)

  defp when_label(%DateTime{} = dt), do: Calendar.strftime(dt, "%a %d %b %H:%M")

  defp time_range(%{starts_at: nil}), do: nil

  defp time_range(%{starts_at: starts, ends_at: ends}),
    do: "#{when_label(starts)} → #{when_label(ends)}"

  defp qty(%Decimal{} = d), do: Decimal.to_string(Decimal.normalize(d), :normal)
  defp qty(other), do: to_string(other)

  defp drop_error(:wrong_machine), do: gettext("A step can only run on its own machine.")
  defp drop_error(_), do: gettext("Could not schedule that step.")

  defp advance_error(:line_blocked),
    do: gettext("This line is waiting on another line to finish.")

  defp advance_error(:order_not_in_production),
    do: gettext("Steps can only be advanced once the order is in production.")

  defp advance_error(_), do: gettext("Could not update that step.")
end
