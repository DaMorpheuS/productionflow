defmodule ProductionflowWeb.Catalog.RouteStepLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Catalog, Production}
  alias Productionflow.Catalog.RouteStep

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@template.name}</:subtitle>
      </.header>

      <.form for={@form} id="route-step-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:machine_id]}
            type="select"
            label={gettext("Machine")}
            prompt={gettext("Choose a machine")}
            options={@machine_options}
            required
          />
          <.input
            field={@form[:quantity_per_unit]}
            type="number"
            step="any"
            label={gettext("Machine units per product unit")}
            required
          />
        </div>

        <fieldset :if={@modifiers != []} class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Apply time modifiers")}</legend>
          <input type="hidden" name="route_step[time_modifier_ids][]" value="" />
          <div class="mt-2 grid gap-2 sm:grid-cols-2">
            <label :for={modifier <- @modifiers} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                name="route_step[time_modifier_ids][]"
                value={modifier.id}
                checked={to_string(modifier.id) in @selected_modifier_ids}
              />
              {modifier.name}
            </label>
          </div>
        </fieldset>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save step")}
          </.button>
          <.button navigate={~p"/catalog/products/#{@template}"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => template_id} = params, _session, socket) do
    template = Catalog.get_product_template!(template_id)

    socket =
      socket
      |> assign(:template, template)
      |> assign(:machine_options, machine_options())

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    step = %RouteStep{}

    socket
    |> assign(:page_title, gettext("New route step"))
    |> assign(:step, step)
    |> assign_machine(nil, [])
    |> assign_form(Catalog.change_route_step(step))
  end

  defp apply_action(socket, :edit, %{"step_id" => step_id}) do
    step = Catalog.get_route_step!(step_id)

    socket
    |> assign(:page_title, gettext("Edit route step"))
    |> assign(:step, step)
    |> assign_machine(step.machine_id, step.time_modifier_ids)
    |> assign_form(Catalog.change_route_step(step))
  end

  @impl true
  def handle_event("validate", %{"route_step" => params}, socket) do
    selected = params |> Map.get("time_modifier_ids", []) |> Enum.reject(&(&1 == ""))
    changeset = Catalog.change_route_step(socket.assigns.step, params)

    {:noreply,
     socket
     |> assign_machine(params["machine_id"], selected, keep_selected: true)
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"route_step" => params}, socket) do
    save_step(socket, socket.assigns.live_action, params)
  end

  defp save_step(socket, :new, params) do
    case Catalog.add_route_step(socket.assigns.template, params) do
      {:ok, _step} -> saved(socket, gettext("Step added."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_step(socket, :edit, params) do
    case Catalog.update_route_step(socket.assigns.step, params) do
      {:ok, _step} -> saved(socket, gettext("Step updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/catalog/products/#{socket.assigns.template}")}
  end

  # Loads the chosen machine's time modifiers (for the checkbox group) and the
  # currently selected ids.
  defp assign_machine(socket, machine_id, selected_ids, opts \\ []) do
    modifiers =
      case blank_to_nil(machine_id) do
        nil -> []
        id -> Production.get_machine!(id).time_modifiers
      end

    selected =
      if opts[:keep_selected], do: selected_ids, else: Enum.map(selected_ids, &to_string/1)

    socket
    |> assign(:modifiers, modifiers)
    |> assign(:selected_modifier_ids, MapSet.new(selected))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "route_step"))
  end

  defp machine_options do
    Production.list_machines() |> Enum.map(&{&1.name, &1.id})
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
