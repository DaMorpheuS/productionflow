defmodule ProductionflowWeb.Orders.OrderLive.Show do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.{Orders, Catalog, CRM}
  alias Productionflow.Orders.Order
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:template_options, template_options())
     |> assign(:add_line, %{"product_template_id" => "", "quantity" => "100"})
     |> load_order(id)}
  end

  defp load_order(socket, id) do
    order = Orders.get_order!(id)

    socket
    |> assign(:order, order)
    |> assign(:page_title, order.number)
    |> assign(:can_edit, socket.assigns.can_manage and Order.editable?(order))
    |> assign(:totals, Orders.order_totals(order))
    |> assign(:all_done, Orders.all_steps_done?(order.id))
    |> assign(:address_options, address_options(order))
  end

  defp address_options(order) do
    CRM.get_relation!(order.relation_id).addresses
    |> Enum.map(&{format_address(&1), &1.id})
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
          <.button :if={@can_edit} navigate={~p"/orders/#{@order}/edit"}>
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

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4">
          <.field label={gettext("Customer")} value={@order.relation.name} />
          <.field label={gettext("Reference")} value={@order.reference} />
          <.field label={gettext("Order date")} value={@order.order_date} />
          <.field label={gettext("Due date")} value={@order.due_date} />
          <.field label={gettext("Total price")} value={money(@totals.price)} />
          <.field label={gettext("Total cost")} value={money(@totals.cost)} />
          <.field label={gettext("Total margin")} value={money(@totals.margin)} />
        </dl>
        <p :if={@order.notes} class="mt-4 whitespace-pre-line border-t border-base-200 pt-3 text-sm">
          {@order.notes}
        </p>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-3 text-base font-semibold">{gettext("Lines")}</h2>

        <p :if={@order.lines == []} class="text-sm text-base-content/60">
          {gettext("No lines yet.")}
        </p>

        <.link
          :for={line <- @order.lines}
          navigate={~p"/orders/#{@order}/lines/#{line}"}
          class="mb-2 flex items-center justify-between gap-4 rounded-lg border border-base-200 p-3 hover:bg-base-200/40"
        >
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span class="font-medium">{qty(line.quantity)} {line.output_unit}</span>
            <span>{line.description}</span>
            <span :if={materials_summary(line) != ""} class="text-sm text-base-content/60">
              · {materials_summary(line)}
            </span>
          </div>
          <div class="flex items-center gap-3">
            <span class={["badge badge-sm", step_status_class(Orders.line_status(line))]}>
              {status_label(Orders.line_status(line))}
            </span>
            <span class="text-sm font-medium">{money(line.total_price)}</span>
          </div>
        </.link>

        <.form
          :if={@can_edit}
          for={%{}}
          id="add-line-form"
          phx-submit="add_line"
          class="mt-3 grid items-end gap-3 sm:grid-cols-3"
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
          :if={@can_edit}
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
        <h2 class="mb-3 text-base font-semibold">{gettext("Deliveries")}</h2>

        <p :if={@order.deliveries == []} class="text-sm text-base-content/60">
          {gettext("No delivery addresses yet.")}
        </p>

        <div :for={delivery <- @order.deliveries} class="mb-4 rounded-lg border border-base-200 p-4">
          <div class="flex items-start justify-between gap-4">
            <div class="text-sm">
              <div class="font-medium">{format_address(delivery)}</div>
              <div :if={delivery.planned_date} class="text-base-content/60">
                {gettext("Planned")}: {delivery.planned_date}
              </div>
            </div>
            <.link
              :if={@can_edit}
              phx-click="delete_delivery"
              phx-value-id={delivery.id}
              data-confirm={gettext("Remove this delivery?")}
              class="text-sm text-error"
            >
              {gettext("Remove")}
            </.link>
          </div>

          <.form
            :if={delivery.items != []}
            for={%{}}
            id={"delivery-items-#{delivery.id}"}
            phx-submit="save_delivery_items"
            class="mt-3 space-y-1"
          >
            <div :for={item <- delivery.items} class="flex items-center gap-2 text-sm">
              <span class="flex-1">{line_description(@order, item.order_line_id)}</span>
              <input
                :if={@can_edit}
                type="number"
                step="any"
                min="0"
                name={"items[#{item.id}]"}
                value={qty(item.quantity)}
                class="input input-sm w-28"
              />
              <span :if={not @can_edit}>{qty(item.quantity)}</span>
            </div>
            <.button :if={@can_edit} class="mt-1">{gettext("Save quantities")}</.button>
          </.form>
        </div>

        <.form
          :if={@can_edit}
          for={%{}}
          id="add-delivery-form"
          phx-submit="add_delivery"
          class="mt-2 grid items-end gap-3 border-t border-base-200 pt-3 sm:grid-cols-3"
        >
          <.input
            :if={@address_options != []}
            name="address_id"
            value=""
            type="select"
            label={gettext("Customer address")}
            prompt={gettext("— or type a new one below —")}
            options={@address_options}
          />
          <.input name="street" value="" type="text" label={gettext("Street")} />
          <.input name="postal_code" value="" type="text" label={gettext("Postal code")} />
          <.input name="city" value="" type="text" label={gettext("City")} />
          <.input name="country" value="" type="text" label={gettext("Country")} />
          <.input name="planned_date" value="" type="date" label={gettext("Planned date")} />
          <label class="flex items-center gap-2 text-sm">
            <input type="hidden" name="save_to_customer" value="false" />
            <input type="checkbox" name="save_to_customer" value="true" class="checkbox checkbox-sm" />
            {gettext("Save address to customer")}
          </label>
          <div class="sm:col-span-3">
            <.button phx-disable-with={gettext("Adding...")}>{gettext("Add delivery")}</.button>
          </div>
        </.form>
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

  def handle_event("add_delivery", params, socket) do
    authorize(socket, fn ->
      case Orders.add_delivery(socket.assigns.order, params) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Delivery added."))}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, gettext("Pick an address or enter a street and city."))}
      end
    end)
  end

  def handle_event("delete_delivery", %{"id" => id}, socket) do
    authorize(socket, fn ->
      case Orders.get_delivery!(id) |> Orders.delete_delivery() do
        {:ok, _} -> {:noreply, reload(socket, gettext("Delivery removed."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not remove it."))}
      end
    end)
  end

  def handle_event("save_delivery_items", %{"items" => items}, socket) do
    authorize(socket, fn ->
      Enum.each(items, fn {item_id, quantity} ->
        Orders.get_delivery_item!(item_id) |> Orders.update_delivery_item(quantity)
      end)

      {:noreply, reload(socket, gettext("Quantities saved."))}
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

  defp materials_summary(line) do
    line.materials |> Enum.map(& &1.material_name) |> Enum.join(", ")
  end

  defp format_address(%{street: street, postal_code: postal, city: city, country: country}) do
    [street, [postal, city] |> Enum.reject(&blank?/1) |> Enum.join(" "), country]
    |> Enum.reject(&blank?/1)
    |> Enum.join(", ")
  end

  defp blank?(value), do: value in [nil, ""]

  defp qty(%Decimal{} = d), do: Decimal.to_string(Decimal.normalize(d), :normal)

  defp line_description(order, line_id) do
    case Enum.find(order.lines, &(&1.id == line_id)) do
      nil -> gettext("Line")
      line -> line.description
    end
  end
end
