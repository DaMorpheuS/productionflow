defmodule ProductionflowWeb.Production.MachineLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Production, Accounts}
  alias Productionflow.Production.Machine

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="machine-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input
            field={@form[:output_unit]}
            type="text"
            label={gettext("Output unit (pieces, m, m², kg…)")}
            required
          />
        </div>

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Time")}</legend>
          <div class="mt-2 grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:units_per_hour]}
              type="number"
              step="0.01"
              label={gettext("Units per hour")}
              required
            />
            <.input
              field={@form[:setup_minutes]}
              type="number"
              step="0.01"
              label={gettext("Setup minutes")}
            />
          </div>
        </fieldset>

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Working hours")}</legend>
          <p class="text-xs text-base-content/60">
            {gettext("Used by the planning board to schedule this machine's queue over time.")}
          </p>
          <div class="mt-2 grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:working_day_start]}
              type="time"
              label={gettext("Day starts at")}
            />
            <.input field={@form[:working_day_end]} type="time" label={gettext("Day ends at")} />
          </div>
          <div class="mt-3">
            <span class="text-sm">{gettext("Working days")}</span>
            <input type="hidden" name="machine[working_days][]" value="" />
            <div class="mt-1 flex flex-wrap gap-3">
              <label :for={{label, day} <- weekday_options()} class="flex items-center gap-1 text-sm">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  name="machine[working_days][]"
                  value={day}
                  checked={day in @selected_working_days}
                />
                {label}
              </label>
            </div>
          </div>
        </fieldset>

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Cost basis")}</legend>
          <div class="mt-2 grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:purchase_price]}
              type="number"
              step="0.01"
              label={gettext("Purchase price (€)")}
            />
            <.input
              field={@form[:residual_value]}
              type="number"
              step="0.01"
              label={gettext("Residual value (€)")}
            />
            <.input
              field={@form[:lifetime_years]}
              type="number"
              step="0.01"
              label={gettext("Lifetime (years)")}
            />
            <.input
              field={@form[:yearly_maintenance_cost]}
              type="number"
              step="0.01"
              label={gettext("Yearly maintenance (€)")}
            />
            <.input
              field={@form[:productive_hours_per_year]}
              type="number"
              step="0.01"
              label={gettext("Productive hours / year")}
            />
            <.input
              field={@form[:power_kw]}
              type="number"
              step="0.01"
              label={gettext("Power draw (kW)")}
            />
          </div>
        </fieldset>

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Operators")}</legend>
          <p class="text-xs text-base-content/60">
            {gettext("Labour cost/hour is the sum of the selected operators' rates.")}
          </p>
          <input type="hidden" name="machine[operator_ids][]" value="" />
          <div class="mt-2 grid gap-2 sm:grid-cols-2">
            <label :for={user <- @users} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                name="machine[operator_ids][]"
                value={user.id}
                checked={to_string(user.id) in @selected_operator_ids}
              />
              {user.email} ({money(user.hourly_cost)}/h)
            </label>
          </div>
        </fieldset>

        <div class="mt-6 rounded-xl border border-base-300 bg-base-200 p-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            {gettext("Internal cost per hour (live)")}
          </p>
          <dl class="mt-2 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
            <.cost label={gettext("Machine")} value={money(@preview.machine)} />
            <.cost label={gettext("Labour")} value={money(@preview.labour)} />
            <.cost label={gettext("Energy")} value={money(@preview.energy)} />
            <.cost label={gettext("Total")} value={money(@preview.total)} emphasize />
          </dl>
        </div>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save machine")}
          </.button>
          <.button navigate={cancel_path(@machine)}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :emphasize, :boolean, default: false

  defp cost(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd class={["", @emphasize && "font-semibold"]}>{@value}</dd>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:settings, Production.get_settings())
      |> assign(:users, Accounts.list_users() |> Enum.filter(& &1.active))

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    machine = %Machine{operators: []}

    socket
    |> assign(:page_title, gettext("New machine"))
    |> assign(:machine, machine)
    |> assign(:selected_operator_ids, MapSet.new())
    |> assign(:selected_working_days, machine.working_days)
    |> assign_form(Production.change_machine(machine))
    |> recompute_preview(machine)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    machine = Production.get_machine!(id)
    operator_ids = machine.operators |> Enum.map(&to_string(&1.id)) |> MapSet.new()

    socket
    |> assign(:page_title, gettext("Edit machine"))
    |> assign(:machine, machine)
    |> assign(:selected_operator_ids, operator_ids)
    |> assign(:selected_working_days, machine.working_days)
    |> assign_form(Production.change_machine(machine))
    |> recompute_preview(machine)
  end

  @impl true
  def handle_event("validate", %{"machine" => params}, socket) do
    operator_ids = Map.get(params, "operator_ids", [])
    changeset = Production.change_machine(socket.assigns.machine, params, operator_ids)
    preview = Ecto.Changeset.apply_changes(changeset)

    {:noreply,
     socket
     |> assign_form(Map.put(changeset, :action, :validate))
     |> assign(:selected_operator_ids, MapSet.new(Enum.reject(operator_ids, &(&1 == ""))))
     |> assign(:selected_working_days, working_days_from(params))
     |> recompute_preview(preview)}
  end

  def handle_event("save", %{"machine" => params}, socket) do
    operator_ids = Map.get(params, "operator_ids", [])
    save_machine(socket, socket.assigns.live_action, params, operator_ids)
  end

  defp save_machine(socket, :new, params, operator_ids) do
    case Production.create_machine(params, operator_ids) do
      {:ok, machine} -> saved(socket, machine, gettext("Machine created."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_machine(socket, :edit, params, operator_ids) do
    case Production.update_machine(socket.assigns.machine, params, operator_ids) do
      {:ok, machine} -> saved(socket, machine, gettext("Machine updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, machine, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/production/machines/#{machine}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "machine"))
  end

  # Builds the live cost preview from a (possibly partial) machine struct.
  defp recompute_preview(socket, machine) do
    settings = socket.assigns.settings
    machine = %{machine | operators: selected_operators(socket)}

    assign(socket, :preview, %{
      machine: Production.machine_cost_per_hour(machine),
      labour: Production.labour_cost_per_hour(machine),
      energy: Production.energy_cost_per_hour(machine, settings),
      total: Production.internal_cost_per_hour(machine, settings)
    })
  end

  defp selected_operators(socket) do
    ids = socket.assigns.selected_operator_ids
    Enum.filter(socket.assigns.users, &(to_string(&1.id) in ids))
  end

  defp cancel_path(%Machine{id: nil}), do: ~p"/production/machines"
  defp cancel_path(machine), do: ~p"/production/machines/#{machine}"

  defp working_days_from(params) do
    params
    |> Map.get("working_days", [])
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_integer/1)
  end

  defp weekday_options do
    [
      {gettext("Mon"), 1},
      {gettext("Tue"), 2},
      {gettext("Wed"), 3},
      {gettext("Thu"), 4},
      {gettext("Fri"), 5},
      {gettext("Sat"), 6},
      {gettext("Sun"), 7}
    ]
  end
end
