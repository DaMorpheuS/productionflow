defmodule ProductionflowWeb.Orders.OrderLive.Show do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.{Orders, Catalog, Production, Inventory}
  alias Productionflow.Orders.{Order, OrderLine}
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:template_options, template_options())
     |> assign(:machine_options, machine_options())
     |> assign(:material_options, material_options())
     |> assign(:add_line, %{"product_template_id" => "", "quantity" => "100"})
     |> load_order(id)}
  end

  defp load_order(socket, id) do
    order = Orders.get_order!(id)

    socket
    |> assign(:order, order)
    |> assign(:page_title, order.number)
    |> assign(:totals, Orders.order_totals(order))
    |> assign(:all_done, Orders.all_steps_done?(order.id))
  end

  defp reload(socket, message) do
    socket |> put_flash(:info, message) |> load_order(socket.assigns.order.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@order.number}
        <span class={["badge ml-2", order_status_class(@order.status)]}>
          {status_label(@order.status)}
        </span>
        <:subtitle>
          <.link navigate={~p"/orders"} class="hover:underline">
            &larr; {gettext("All orders")}
          </.link>
          · {@order.relation.name}
        </:subtitle>
        <:actions>
          <.button :if={@can_manage and @order.status == :draft} navigate={~p"/orders/#{@order}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button
            :if={@can_manage and :confirmed in Order.next_statuses(@order.status)}
            phx-click="transition"
            phx-value-status="confirmed"
          >
            {gettext("Confirm")}
          </.button>
          <.button
            :if={@can_manage and :in_production in Order.next_statuses(@order.status)}
            variant="primary"
            phx-click="transition"
            phx-value-status="in_production"
          >
            {gettext("Start production")}
          </.button>
          <.button
            :if={@can_manage and @order.status == :in_production and @all_done}
            variant="primary"
            phx-click="complete"
            data-confirm={gettext("Complete this order and consume material stock?")}
          >
            {gettext("Complete")}
          </.button>
          <.button
            :if={@can_manage and :cancelled in Order.next_statuses(@order.status)}
            phx-click="transition"
            phx-value-status="cancelled"
            data-confirm={gettext("Cancel this order?")}
          >
            {gettext("Cancel")}
          </.button>
        </:actions>
      </.header>

      <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
        <.field label={gettext("Customer")} value={@order.relation.name} />
        <.field label={gettext("Reference")} value={@order.reference} />
        <.field label={gettext("Order date")} value={@order.order_date} />
        <.field label={gettext("Due date")} value={@order.due_date} />
      </dl>

      <div :if={@order.notes} class="rounded-xl border border-base-300 bg-base-100 p-4 text-sm">
        <p class="whitespace-pre-line">{@order.notes}</p>
      </div>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-base font-semibold">{gettext("Lines")}</h2>
        </div>

        <p :if={@order.lines == []} class="text-sm text-base-content/60">
          {gettext("No lines yet.")}
        </p>

        <div :for={line <- @order.lines} class="mb-4 rounded-lg border border-base-200 p-4">
          <div class="flex items-start justify-between gap-4">
            <div>
              <span class="font-medium">{line.description}</span>
              <span class="text-base-content/60">
                — {Decimal.to_string(line.quantity)} {line.output_unit}
              </span>
              <span class={["badge badge-sm ml-2", step_status_class(Orders.line_status(line))]}>
                {status_label(Orders.line_status(line))}
              </span>
            </div>
            <div class="flex items-center gap-3 text-sm">
              <span>{gettext("Price")}: <strong>{money(line.total_price)}</strong></span>
              <span class="text-base-content/60">
                {gettext("cost")} {money(line.internal_total_cost)} · {gettext("margin")} {money(
                  line.total_margin
                )}
              </span>
              <.link
                :if={@can_manage and @order.status == :draft}
                phx-click="delete_line"
                phx-value-id={line.id}
                data-confirm={gettext("Remove this line?")}
                class="text-error"
              >
                {gettext("Remove")}
              </.link>
            </div>
          </div>

          <div :if={line.route_steps != []} class="mt-3">
            <h3 class="text-xs font-semibold uppercase text-base-content/50">{gettext("Route")}</h3>
            <ul class="divide-y divide-base-200">
              <li
                :for={step <- line.route_steps}
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
                  :if={@can_manage and @order.status == :draft and OrderLine.ad_hoc?(line)}
                  phx-click="delete_line_step"
                  phx-value-id={step.id}
                  data-confirm={gettext("Delete this step?")}
                  class="text-xs text-error"
                >
                  {gettext("Delete")}
                </.link>
              </li>
            </ul>
          </div>

          <div :if={line.materials != []} class="mt-3">
            <h3 class="text-xs font-semibold uppercase text-base-content/50">
              {gettext("Materials")}
            </h3>
            <ul class="text-sm text-base-content/70">
              <li :for={mat <- line.materials} class="flex items-center gap-2">
                <span>
                  {mat.material_name} — {Decimal.to_string(mat.quantity)} {mat.unit} ({money(mat.cost)})
                </span>
                <span :if={mat.consumed_at} class="text-success">· {gettext("consumed")}</span>
                <.link
                  :if={@can_manage and @order.status == :draft and OrderLine.ad_hoc?(line)}
                  phx-click="delete_line_material"
                  phx-value-id={mat.id}
                  data-confirm={gettext("Delete this material?")}
                  class="text-error"
                >
                  {gettext("×")}
                </.link>
              </li>
            </ul>
          </div>

          <div
            :if={@can_manage and @order.status == :draft and OrderLine.ad_hoc?(line)}
            class="mt-3 space-y-2 border-t border-base-200 pt-3"
          >
            <.form
              for={%{}}
              id={"add-step-#{line.id}"}
              phx-submit="add_line_step"
              class="flex flex-wrap items-end gap-2"
            >
              <input type="hidden" name="line_id" value={line.id} />
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
            <.form
              for={%{}}
              id={"add-mat-#{line.id}"}
              phx-submit="add_line_material"
              class="flex flex-wrap items-end gap-2"
            >
              <input type="hidden" name="line_id" value={line.id} />
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
          </div>

          <.form
            :if={@can_manage and @order.status == :draft and other_lines(@order, line) != []}
            for={%{}}
            id={"deps-#{line.id}"}
            phx-submit="set_dependencies"
            class="mt-3 flex flex-wrap items-end gap-2 border-t border-base-200 pt-3"
          >
            <input type="hidden" name="line_id" value={line.id} />
            <label class="text-sm">
              <span class="block text-xs text-base-content/60">
                {gettext("Depends on (must finish first)")}
              </span>
              <select name="depends_on_ids[]" multiple class="select select-sm h-auto min-w-48">
                <option
                  :for={{label, id} <- other_lines(@order, line)}
                  value={id}
                  selected={id in dependency_ids(line)}
                >
                  {label}
                </option>
              </select>
            </label>
            <.button>{gettext("Save")}</.button>
          </.form>
        </div>

        <.form
          :if={@can_manage and @order.status == :draft}
          for={%{}}
          id="add-line-form"
          phx-submit="add_line"
          class="mt-2 grid items-end gap-3 sm:grid-cols-3"
        >
          <.input
            name="product_template_id"
            value={@add_line["product_template_id"]}
            type="select"
            label={gettext("Add product")}
            prompt={gettext("Choose a product")}
            options={@template_options}
          />
          <.input
            name="quantity"
            value={@add_line["quantity"]}
            type="number"
            step="1"
            min="0"
            label={gettext("Quantity")}
          />
          <div>
            <.button variant="primary" phx-disable-with={gettext("Adding...")}>
              {gettext("Add line")}
            </.button>
          </div>
        </.form>

        <.form
          :if={@can_manage and @order.status == :draft}
          for={%{}}
          id="add-custom-line-form"
          phx-submit="add_blank_line"
          class="mt-3 grid items-end gap-3 border-t border-base-200 pt-3 sm:grid-cols-4"
        >
          <.input
            name="description"
            value=""
            type="text"
            label={gettext("Custom line")}
            placeholder={gettext("Description")}
          />
          <.input name="output_unit" value="" type="text" label={gettext("Unit")} />
          <.input
            name="quantity"
            value="1"
            type="number"
            step="1"
            min="0"
            label={gettext("Quantity")}
          />
          <.input
            name="unit_price"
            value=""
            type="number"
            step="0.01"
            min="0"
            label={gettext("Manual price (optional)")}
          />
          <div class="sm:col-span-4">
            <.button phx-disable-with={gettext("Adding...")}>{gettext("Add custom line")}</.button>
          </div>
        </.form>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <dl class="grid grid-cols-3 gap-x-6 text-sm">
          <.field label={gettext("Total price")} value={money(@totals.price)} />
          <.field label={gettext("Total cost")} value={money(@totals.cost)} />
          <.field label={gettext("Total margin")} value={money(@totals.margin)} />
        </dl>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  ## Events

  @impl true
  def handle_event("transition", %{"status" => status}, socket) do
    authorize(socket, fn ->
      case Orders.transition_order(socket.assigns.order, String.to_existing_atom(status)) do
        {:ok, _order} ->
          {:noreply, reload(socket, gettext("Order updated."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("That change is not allowed."))}
      end
    end)
  end

  def handle_event("complete", _params, socket) do
    authorize(socket, fn ->
      case Orders.complete_order(socket.assigns.order, socket.assigns.current_scope.user) do
        {:ok, _order} ->
          {:noreply, reload(socket, gettext("Order completed; stock consumed."))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, complete_error(reason))}
      end
    end)
  end

  def handle_event("advance_step", %{"id" => id, "status" => status}, socket) do
    authorize(socket, fn ->
      step = Orders.get_route_step!(id)

      case Orders.advance_step(step, String.to_existing_atom(status)) do
        {:ok, _step} ->
          {:noreply, reload(socket, gettext("Step updated."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("That change is not allowed."))}
      end
    end)
  end

  def handle_event("add_line", %{"product_template_id" => "", "quantity" => _}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Choose a product first."))}
  end

  def handle_event("add_line", %{"product_template_id" => template_id, "quantity" => qty}, socket) do
    authorize(socket, fn ->
      case Orders.add_line_from_template(socket.assigns.order, template_id, qty) do
        {:ok, _line} -> {:noreply, reload(socket, gettext("Line added."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not add the line."))}
      end
    end)
  end

  def handle_event("delete_line", %{"id" => id}, socket) do
    authorize(socket, fn ->
      case Orders.get_line!(id) |> Orders.delete_line() do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Line removed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the line."))}
      end
    end)
  end

  def handle_event("add_blank_line", params, socket) do
    authorize(socket, fn ->
      case Orders.add_blank_line(socket.assigns.order, params) do
        {:ok, _line} ->
          {:noreply, reload(socket, gettext("Custom line added."))}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, gettext("A description and quantity are required."))}
      end
    end)
  end

  def handle_event("add_line_step", %{"line_id" => line_id} = params, socket) do
    authorize(socket, fn ->
      case Orders.add_line_route_step(Orders.get_line!(line_id), params) do
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

  def handle_event("add_line_material", %{"line_id" => line_id} = params, socket) do
    authorize(socket, fn ->
      case Orders.add_line_material(Orders.get_line!(line_id), params) do
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

  def handle_event("set_dependencies", %{"line_id" => line_id} = params, socket) do
    authorize(socket, fn ->
      ids = Map.get(params, "depends_on_ids", [])

      case Orders.set_line_dependencies(Orders.get_line!(line_id), ids) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Dependencies saved."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not save dependencies."))}
      end
    end)
  end

  defp authorize(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  defp complete_error(:steps_unfinished), do: gettext("Every route step must be done first.")
  defp complete_error(:not_in_production), do: gettext("The order is not in production.")
  defp complete_error(_), do: gettext("Could not complete the order.")

  defp template_options do
    Catalog.list_product_templates() |> Enum.map(&{&1.name, &1.id})
  end

  defp machine_options do
    Production.list_machines() |> Enum.map(&{&1.name, &1.id})
  end

  defp material_options do
    Inventory.list_materials() |> Enum.map(&{"#{&1.name} (#{&1.unit})", &1.id})
  end

  # Other lines of the order, as {label, id}, for the dependency picker.
  defp other_lines(order, line) do
    order.lines
    |> Enum.reject(&(&1.id == line.id))
    |> Enum.map(&{&1.description, &1.id})
  end

  defp dependency_ids(%OrderLine{depends_on: deps}) when is_list(deps),
    do: Enum.map(deps, & &1.id)

  defp dependency_ids(_line), do: []
end
