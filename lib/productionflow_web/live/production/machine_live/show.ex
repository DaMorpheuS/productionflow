defmodule ProductionflowWeb.Production.MachineLive.Show do
  use ProductionflowWeb, :live_view

  alias Productionflow.Production
  alias Productionflow.Production.TimeModifier
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    machine = Production.get_machine!(id)

    {:ok,
     socket
     |> assign(:page_title, machine.name)
     |> assign(:settings, Production.get_settings())
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "production.manage"))
     |> assign(:modifier_form, modifier_form())
     |> assign(:quantity, "1")
     |> assign(:selected_modifier_ids, [])
     |> assign_machine(machine)}
  end

  defp assign_machine(socket, machine) do
    socket
    |> assign(:machine, machine)
    |> stream(:time_modifiers, machine.time_modifiers, reset: true)
    |> recompute_estimate()
  end

  defp modifier_form(attrs \\ %{}),
    do: to_form(Production.change_time_modifier(attrs), as: "modifier")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@machine.name}
        <span :if={@machine.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        <:subtitle>
          <.link navigate={~p"/production/machines"} class="hover:underline">
            &larr; {gettext("All machines")}
          </.link>
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/production/machines/#{@machine}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button :if={@can_manage and is_nil(@machine.archived_at)} phx-click="archive">
            {gettext("Archive")}
          </.button>
          <.button :if={@can_manage and @machine.archived_at} phx-click="unarchive">
            {gettext("Unarchive")}
          </.button>
        </:actions>
      </.header>

      <div class="rounded-xl border border-base-300 bg-base-100 p-6">
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <.detail label={gettext("Output unit")} value={@machine.output_unit} />
          <.detail label={gettext("Units / hour")} value={Decimal.to_string(@machine.units_per_hour)} />
          <.detail label={gettext("Setup minutes")} value={Decimal.to_string(@machine.setup_minutes)} />
          <.detail label={gettext("Power draw")} value={"#{Decimal.to_string(@machine.power_kw)} kW"} />
        </dl>

        <p class="mt-4 text-xs font-semibold uppercase tracking-wide text-base-content/50">
          {gettext("Internal cost per hour")}
        </p>
        <dl class="mt-1 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
          <.detail
            label={gettext("Machine")}
            value={money(Production.machine_cost_per_hour(@machine))}
          />
          <.detail label={gettext("Labour")} value={money(Production.labour_cost_per_hour(@machine))} />
          <.detail
            label={gettext("Energy")}
            value={money(Production.energy_cost_per_hour(@machine, @settings))}
          />
          <.detail
            label={gettext("Total")}
            value={money(Production.internal_cost_per_hour(@machine, @settings))}
          />
        </dl>
      </div>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Time modifiers")}</h2>
        <.form
          :if={@can_manage}
          for={@modifier_form}
          id="modifier-form"
          phx-submit="add_modifier"
          class="mb-4 flex flex-wrap items-end gap-2"
        >
          <.input field={@modifier_form[:name]} type="text" label={gettext("Name")} />
          <.input
            field={@modifier_form[:kind]}
            type="select"
            label={gettext("Kind")}
            options={kind_options()}
          />
          <.input field={@modifier_form[:value]} type="number" step="0.01" label={gettext("Value")} />
          <.button variant="primary">{gettext("Add")}</.button>
        </.form>

        <ul id="time-modifiers" phx-update="stream" class="divide-y divide-base-200">
          <li id="time-modifiers-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No time modifiers yet.")}
          </li>
          <li :for={{id, mod} <- @streams.time_modifiers} id={id} class="flex items-center gap-4 py-2">
            <span class="flex-1 text-sm">
              {mod.name} — <span class="text-base-content/70">{modifier_label(mod)}</span>
            </span>
            <.link
              :if={@can_manage}
              phx-click="delete_modifier"
              phx-value-id={mod.id}
              data-confirm={gettext("Delete this modifier?")}
              class="text-sm"
            >
              {gettext("Delete")}
            </.link>
          </li>
        </ul>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Estimate")}</h2>
        <.form
          for={%{}}
          id="estimate-form"
          phx-change="estimate"
          class="flex flex-wrap items-end gap-3"
        >
          <label class="text-sm">
            <span class="block">{gettext("Quantity")} ({@machine.output_unit})</span>
            <input
              type="number"
              name="quantity"
              value={@quantity}
              step="0.01"
              min="0"
              phx-debounce="300"
              class="input"
            />
          </label>
          <div :if={@machine.time_modifiers != []} class="text-sm">
            <span class="block">{gettext("Apply modifiers")}</span>
            <input type="hidden" name="modifiers[]" value="" />
            <label :for={mod <- @machine.time_modifiers} class="mr-3 inline-flex items-center gap-1">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                name="modifiers[]"
                value={mod.id}
                checked={to_string(mod.id) in @selected_modifier_ids}
              />
              {mod.name}
            </label>
          </div>
        </.form>

        <dl :if={@estimate} class="mt-4 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-5">
          <.detail label={gettext("Duration")} value={duration(@estimate.duration_minutes)} />
          <.detail label={gettext("Machine")} value={money(@estimate.machine_cost)} />
          <.detail label={gettext("Labour")} value={money(@estimate.labour_cost)} />
          <.detail label={gettext("Energy")} value={money(@estimate.energy_cost)} />
          <.detail label={gettext("Total")} value={money(@estimate.total_cost)} />
        </dl>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp detail(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  ## Events

  @impl true
  def handle_event("estimate", params, socket) do
    quantity = params["quantity"] || ""
    modifier_ids = params |> Map.get("modifiers", []) |> Enum.reject(&(&1 == ""))

    {:noreply,
     socket
     |> assign(:quantity, quantity)
     |> assign(:selected_modifier_ids, modifier_ids)
     |> recompute_estimate()}
  end

  def handle_event("add_modifier", %{"modifier" => params}, socket) do
    authorize(socket, fn ->
      case Production.add_time_modifier(socket.assigns.machine, params) do
        {:ok, _modifier} ->
          machine = Production.get_machine!(socket.assigns.machine.id)

          {:noreply,
           socket
           |> assign(:modifier_form, modifier_form())
           |> put_flash(:info, gettext("Modifier added."))
           |> assign_machine(machine)}

        {:error, changeset} ->
          {:noreply, assign(socket, :modifier_form, to_form(changeset, as: "modifier"))}
      end
    end)
  end

  def handle_event("delete_modifier", %{"id" => id}, socket) do
    authorize(socket, fn ->
      Production.get_time_modifier!(id) |> Production.delete_time_modifier()
      machine = Production.get_machine!(socket.assigns.machine.id)

      {:noreply,
       socket |> put_flash(:info, gettext("Modifier deleted.")) |> assign_machine(machine)}
    end)
  end

  def handle_event("archive", _params, socket) do
    authorize(socket, fn ->
      {:ok, machine} = Production.archive_machine(socket.assigns.machine)

      {:noreply,
       socket |> assign(:machine, machine) |> put_flash(:info, gettext("Machine archived."))}
    end)
  end

  def handle_event("unarchive", _params, socket) do
    authorize(socket, fn ->
      {:ok, machine} = Production.unarchive_machine(socket.assigns.machine)

      {:noreply,
       socket |> assign(:machine, machine) |> put_flash(:info, gettext("Machine restored."))}
    end)
  end

  defp authorize(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  defp recompute_estimate(socket) do
    machine = socket.assigns.machine

    estimate =
      case parse_quantity(socket.assigns.quantity) do
        nil -> nil
        qty -> Production.estimate(machine, qty, socket.assigns.selected_modifier_ids)
      end

    assign(socket, :estimate, estimate)
  end

  defp parse_quantity(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> if Decimal.compare(decimal, 0) == :gt, do: decimal, else: nil
      _ -> nil
    end
  end

  defp parse_quantity(_), do: nil

  defp kind_options, do: Enum.map(TimeModifier.kinds(), &{Phoenix.Naming.humanize(&1), &1})

  defp modifier_label(%{kind: :percentage, value: value}), do: "+#{Decimal.to_string(value)}%"

  defp modifier_label(%{kind: :fixed_minutes, value: value}),
    do: "+#{Decimal.to_string(value)} min"
end
