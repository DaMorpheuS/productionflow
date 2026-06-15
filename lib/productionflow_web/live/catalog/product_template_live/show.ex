defmodule ProductionflowWeb.Catalog.ProductTemplateLive.Show do
  use ProductionflowWeb, :live_view

  alias Productionflow.Catalog
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    template = Catalog.get_product_template!(id)

    {:ok,
     socket
     |> assign(:page_title, template.name)
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "catalog.manage"))
     |> assign(:quantity, "100")
     |> assign_template(template)}
  end

  defp assign_template(socket, template) do
    socket
    |> assign(:template, template)
    |> stream(:route_steps, template.route_steps, reset: true)
    |> stream(:materials, template.materials, reset: true)
    |> recompute_estimate()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@template.name}
        <span :if={@template.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        <:subtitle>
          <.link navigate={~p"/catalog/products"} class="hover:underline">
            &larr; {gettext("All products")}
          </.link>
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/catalog/products/#{@template}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button :if={@can_manage and is_nil(@template.archived_at)} phx-click="archive">
            {gettext("Archive")}
          </.button>
          <.button :if={@can_manage and @template.archived_at} phx-click="unarchive">
            {gettext("Unarchive")}
          </.button>
        </:actions>
      </.header>

      <div :if={@template.description} class="rounded-xl border border-base-300 bg-base-100 p-6">
        <p class="whitespace-pre-line text-sm">{@template.description}</p>
      </div>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="mb-2 flex items-center justify-between">
          <h2 class="text-base font-semibold">{gettext("Production route")}</h2>
          <.button :if={@can_manage} navigate={~p"/catalog/products/#{@template}/steps/new"}>
            {gettext("Add step")}
          </.button>
        </div>
        <ol id="route-steps" phx-update="stream" class="divide-y divide-base-200">
          <li id="route-steps-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No steps yet.")}
          </li>
          <li
            :for={{id, step} <- @streams.route_steps}
            id={id}
            class="flex items-center gap-4 py-2 text-sm"
          >
            <span class="flex-1">
              <span class="font-medium">{step.machine.name}</span>
              <span class="text-base-content/60">
                — ×{Decimal.to_string(step.quantity_per_unit)} {step.machine.output_unit}/{@template.output_unit}
              </span>
              <span :if={modifier_names(step) != ""} class="text-base-content/50">
                · {modifier_names(step)}
              </span>
            </span>
            <span :if={@can_manage} class="flex gap-3">
              <.link navigate={~p"/catalog/products/#{@template}/steps/#{step}/edit"}>{gettext("Edit")}</.link>
              <.link
                phx-click="delete_step"
                phx-value-id={step.id}
                data-confirm={gettext("Delete this step?")}
              >
                {gettext("Delete")}
              </.link>
            </span>
          </li>
        </ol>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="mb-2 flex items-center justify-between">
          <h2 class="text-base font-semibold">{gettext("Bill of materials")}</h2>
          <.button :if={@can_manage} navigate={~p"/catalog/products/#{@template}/materials/new"}>
            {gettext("Add material")}
          </.button>
        </div>
        <ul id="materials" phx-update="stream" class="divide-y divide-base-200">
          <li id="materials-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No materials yet.")}
          </li>
          <li
            :for={{id, line} <- @streams.materials}
            id={id}
            class="flex items-center gap-4 py-2 text-sm"
          >
            <span class="flex-1">
              <span class="font-medium">{line.material.name}</span>
              <span class="text-base-content/60">
                — {Decimal.to_string(line.quantity_per_unit)} {line.material.unit}/{@template.output_unit}
              </span>
              <span :if={Decimal.compare(line.waste_pct, 0) == :gt} class="text-base-content/50">
                · {Decimal.to_string(line.waste_pct)}% {gettext("waste")}
              </span>
            </span>
            <span :if={@can_manage} class="flex gap-3">
              <.link navigate={~p"/catalog/products/#{@template}/materials/#{line}/edit"}>{gettext(
                "Edit"
              )}</.link>
              <.link
                phx-click="delete_material"
                phx-value-id={line.id}
                data-confirm={gettext("Delete this material?")}
              >
                {gettext("Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Cost & time preview")}</h2>
        <.form for={%{}} id="estimate-form" phx-change="estimate" class="flex items-end gap-3">
          <label class="text-sm">
            <span class="block">{gettext("Quantity")} ({@template.output_unit})</span>
            <input
              type="number"
              name="quantity"
              value={@quantity}
              step="1"
              min="0"
              phx-debounce="300"
              class="input"
            />
          </label>
        </.form>

        <dl :if={@estimate} class="mt-4 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
          <.detail label={gettext("Duration")} value={duration(@estimate.duration_minutes)} />
          <.detail label={gettext("Machine")} value={money(@estimate.machine_cost)} />
          <.detail label={gettext("Labour")} value={money(@estimate.labour_cost)} />
          <.detail label={gettext("Energy")} value={money(@estimate.energy_cost)} />
          <.detail label={gettext("Materials")} value={money(@estimate.material_cost)} />
          <.detail label={gettext("Total internal cost")} value={money(@estimate.total_cost)} />
          <.detail label={gettext("Internal cost per unit")} value={money(@estimate.unit_cost)} />
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
  def handle_event("estimate", %{"quantity" => quantity}, socket) do
    {:noreply, socket |> assign(:quantity, quantity) |> recompute_estimate()}
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    authorize(socket, fn ->
      Catalog.get_route_step!(id) |> Catalog.delete_route_step()
      {:noreply, reload(socket, gettext("Step deleted."))}
    end)
  end

  def handle_event("delete_material", %{"id" => id}, socket) do
    authorize(socket, fn ->
      Catalog.get_template_material!(id) |> Catalog.delete_template_material()
      {:noreply, reload(socket, gettext("Material removed."))}
    end)
  end

  def handle_event("archive", _params, socket) do
    authorize(socket, fn ->
      {:ok, template} = Catalog.archive_product_template(socket.assigns.template)

      {:noreply,
       socket |> assign(:template, template) |> put_flash(:info, gettext("Product archived."))}
    end)
  end

  def handle_event("unarchive", _params, socket) do
    authorize(socket, fn ->
      {:ok, template} = Catalog.unarchive_product_template(socket.assigns.template)

      {:noreply,
       socket |> assign(:template, template) |> put_flash(:info, gettext("Product restored."))}
    end)
  end

  defp reload(socket, message) do
    template = Catalog.get_product_template!(socket.assigns.template.id)
    socket |> put_flash(:info, message) |> assign_template(template)
  end

  defp authorize(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  defp recompute_estimate(socket) do
    estimate =
      case parse_quantity(socket.assigns.quantity) do
        nil -> nil
        qty -> Catalog.estimate(socket.assigns.template, qty)
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

  defp modifier_names(step) do
    step.machine.time_modifiers
    |> Enum.filter(&(&1.id in step.time_modifier_ids))
    |> Enum.map(& &1.name)
    |> Enum.join(", ")
  end
end
