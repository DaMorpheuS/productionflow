defmodule ProductionflowWeb.Orders.OrderLineLive.Show do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.{Orders, Production, Inventory}
  alias Productionflow.Orders.{Order, OrderLine}
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => order_id, "line_id" => line_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:machine_options, machine_options())
     |> assign(:material_options, material_options())
     |> load(order_id, line_id)}
  end

  defp load(socket, order_id, line_id) do
    order = Orders.get_order!(order_id)
    line = Enum.find(order.lines, &(to_string(&1.id) == to_string(line_id)))
    if is_nil(line), do: raise(Ecto.NoResultsError, queryable: OrderLine)

    socket
    |> assign(:order, order)
    |> assign(:line, line)
    |> assign(:can_edit, socket.assigns.can_manage and Order.editable?(order))
    |> assign(:page_title, line.description)
  end

  defp reload(socket, message) do
    socket
    |> put_flash(:info, message)
    |> load(socket.assigns.order.id, socket.assigns.line.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@line.description}
        <span class={["badge ml-2", step_status_class(Orders.line_status(@line))]}>
          {status_label(Orders.line_status(@line))}
        </span>
        <:subtitle>
          <.link navigate={~p"/orders/#{@order}"} class="hover:underline">
            &larr; {gettext("Order %{number}", number: @order.number)}
          </.link>
        </:subtitle>
        <:actions>
          <.button
            :if={@can_edit}
            phx-click="delete_line"
            data-confirm={gettext("Remove this line from the order?")}
          >
            {gettext("Remove line")}
          </.button>
        </:actions>
      </.header>

      <.form
        :if={@can_edit and OrderLine.ad_hoc?(@line)}
        for={%{}}
        id="line-form"
        phx-submit="save_line"
        class="grid items-end gap-3 sm:grid-cols-4"
      >
        <.input
          name="description"
          value={@line.description}
          type="text"
          label={gettext("Description")}
        />
        <.input name="output_unit" value={@line.output_unit} type="text" label={gettext("Unit")} />
        <.input
          name="quantity"
          value={qty(@line.quantity)}
          type="number"
          step="any"
          min="0"
          label={gettext("Quantity")}
        />
        <.input
          name="unit_price"
          value={
            if(@line.price_source == :manual and @line.unit_price,
              do: qty(@line.unit_price),
              else: ""
            )
          }
          type="number"
          step="0.01"
          min="0"
          label={gettext("Manual price (optional)")}
        />
        <div class="sm:col-span-4">
          <.button variant="primary">{gettext("Save line")}</.button>
        </div>
      </.form>

      <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
        <.detail label={gettext("Quantity")} value={"#{qty(@line.quantity)} #{@line.output_unit}"} />
        <.detail label={gettext("Unit price")} value={money(@line.unit_price)} />
        <.detail label={gettext("Total price")} value={money(@line.total_price)} />
        <.detail label={gettext("Total cost")} value={money(@line.internal_total_cost)} />
        <.detail label={gettext("Margin")} value={money(@line.total_margin)} />
      </dl>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Route")}</h2>
        <p :if={@line.route_steps == []} class="text-sm text-base-content/60">
          {gettext("No steps yet.")}
        </p>
        <ul class="divide-y divide-base-200">
          <li
            :for={step <- @line.route_steps}
            class="flex items-center justify-between gap-4 py-1.5 text-sm"
          >
            <span>
              {step.machine_name}
              <span class="text-base-content/60">· {duration(step.duration_minutes)}</span>
              <span class={["badge badge-sm ml-1", step_status_class(step.status)]}>
                {status_label(step.status)}
              </span>
            </span>
            <span :if={@can_manage and @order.status == :in_production} class="flex gap-2">
              <.button
                :if={step.status == :pending}
                phx-click="advance_step"
                phx-value-id={step.id}
                phx-value-status="in_progress"
              >
                {gettext("Start")}
              </.button>
              <.button
                :if={step.status == :in_progress}
                variant="primary"
                phx-click="advance_step"
                phx-value-id={step.id}
                phx-value-status="done"
              >
                {gettext("Done")}
              </.button>
              <.button
                :if={step.status == :done}
                phx-click="advance_step"
                phx-value-id={step.id}
                phx-value-status="in_progress"
              >
                {gettext("Reopen")}
              </.button>
            </span>
            <.link
              :if={@can_edit and OrderLine.ad_hoc?(@line)}
              phx-click="delete_line_step"
              phx-value-id={step.id}
              data-confirm={gettext("Delete this step?")}
              class="text-xs text-error"
            >
              {gettext("Delete")}
            </.link>
          </li>
        </ul>

        <.form
          :if={@can_edit and OrderLine.ad_hoc?(@line)}
          for={%{}}
          id="add-step-form"
          phx-submit="add_line_step"
          class="mt-3 flex flex-wrap items-end gap-2"
        >
          <.input
            name="machine_id"
            value=""
            type="select"
            prompt={gettext("Machine")}
            options={@machine_options}
          />
          <.input
            name="machine_quantity"
            value=""
            type="number"
            step="any"
            min="0"
            placeholder={gettext("Machine qty")}
          />
          <.button>{gettext("Add step")}</.button>
        </.form>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Materials")}</h2>
        <p :if={@line.materials == []} class="text-sm text-base-content/60">
          {gettext("No materials yet.")}
        </p>
        <ul class="text-sm text-base-content/70">
          <li :for={mat <- @line.materials} class="flex items-center gap-2 py-1">
            <span class="flex-1">
              {mat.material_name} — {qty(mat.quantity)} {mat.unit} ({money(mat.cost)})
            </span>
            <span :if={mat.consumed_at} class="text-success">{gettext("consumed")}</span>
            <.link
              :if={@can_edit and OrderLine.ad_hoc?(@line)}
              phx-click="delete_line_material"
              phx-value-id={mat.id}
              data-confirm={gettext("Delete this material?")}
              class="text-error"
            >
              {gettext("×")}
            </.link>
          </li>
        </ul>

        <.form
          :if={@can_edit and OrderLine.ad_hoc?(@line)}
          for={%{}}
          id="add-mat-form"
          phx-submit="add_line_material"
          class="mt-3 flex flex-wrap items-end gap-2"
        >
          <.input
            name="material_id"
            value=""
            type="select"
            prompt={gettext("Material")}
            options={@material_options}
          />
          <.input
            name="quantity"
            value=""
            type="number"
            step="any"
            min="0"
            placeholder={gettext("Quantity")}
          />
          <.button>{gettext("Add material")}</.button>
        </.form>
      </section>

      <section
        :if={@can_edit and other_lines(@order, @line) != []}
        class="rounded-xl border border-base-300 bg-base-100 p-6"
      >
        <h2 class="mb-2 text-base font-semibold">{gettext("Dependencies")}</h2>
        <p class="mb-2 text-sm text-base-content/60">
          {gettext("Lines that must finish before this one can be produced.")}
        </p>
        <.form
          for={%{}}
          id="deps-form"
          phx-submit="set_dependencies"
          class="flex flex-wrap items-end gap-2"
        >
          <select name="depends_on_ids[]" multiple class="select h-auto min-w-64">
            <option
              :for={{label, id} <- other_lines(@order, @line)}
              value={id}
              selected={id in dependency_ids(@line)}
            >
              {label}
            </option>
          </select>
          <.button>{gettext("Save dependencies")}</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

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
  def handle_event("save_line", params, socket) do
    authorize(socket, fn ->
      case Orders.update_line(socket.assigns.line, params) do
        {:ok, _} -> {:noreply, reload(socket, gettext("Line saved."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not save the line."))}
      end
    end)
  end

  def handle_event("advance_step", %{"id" => id, "status" => status}, socket) do
    authorize(socket, fn ->
      step = Orders.get_route_step!(id)

      case Orders.advance_step(step, String.to_existing_atom(status)) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Step updated."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("That change is not allowed."))}
      end
    end)
  end

  def handle_event("add_line_step", params, socket) do
    authorize(socket, fn ->
      case Orders.add_line_route_step(socket.assigns.line, params) do
        {:ok, _} -> {:noreply, reload(socket, gettext("Step added."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not add the step."))}
      end
    end)
  end

  def handle_event("delete_line_step", %{"id" => id}, socket) do
    authorize(socket, fn ->
      case Orders.get_line_route_step!(id) |> Orders.delete_line_route_step() do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Step removed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the step."))}
      end
    end)
  end

  def handle_event("add_line_material", params, socket) do
    authorize(socket, fn ->
      case Orders.add_line_material(socket.assigns.line, params) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Material added."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not add the material."))}
      end
    end)
  end

  def handle_event("delete_line_material", %{"id" => id}, socket) do
    authorize(socket, fn ->
      case Orders.get_line_material!(id) |> Orders.delete_line_material() do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Material removed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the material."))}
      end
    end)
  end

  def handle_event("set_dependencies", params, socket) do
    authorize(socket, fn ->
      ids = Map.get(params, "depends_on_ids", [])

      case Orders.set_line_dependencies(socket.assigns.line, ids) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Dependencies saved."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not save dependencies."))}
      end
    end)
  end

  def handle_event("delete_line", _params, socket) do
    authorize(socket, fn ->
      case Orders.delete_line(socket.assigns.line) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Line removed."))
           |> push_navigate(to: ~p"/orders/#{socket.assigns.order}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the line."))}
      end
    end)
  end

  defp authorize(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  defp machine_options do
    Production.list_machines() |> Enum.map(&{&1.name, &1.id})
  end

  defp material_options do
    Inventory.list_materials() |> Enum.map(&{"#{&1.name} (#{&1.unit})", &1.id})
  end

  defp other_lines(order, line) do
    order.lines
    |> Enum.reject(&(&1.id == line.id))
    |> Enum.map(&{&1.description, &1.id})
  end

  defp dependency_ids(%OrderLine{depends_on: deps}) when is_list(deps),
    do: Enum.map(deps, & &1.id)

  defp dependency_ids(_line), do: []

  defp qty(%Decimal{} = d), do: Decimal.to_string(Decimal.normalize(d), :normal)
  defp qty(_), do: ""
end
