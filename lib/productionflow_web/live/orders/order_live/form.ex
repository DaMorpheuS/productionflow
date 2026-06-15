defmodule ProductionflowWeb.Orders.OrderLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Orders, CRM}
  alias Productionflow.Orders.Order

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="order-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:relation_id]}
            type="select"
            label={gettext("Customer")}
            prompt={gettext("Choose a customer")}
            options={@customer_options}
            required
          />
          <.input field={@form[:reference]} type="text" label={gettext("Reference / PO")} />
          <.input field={@form[:order_date]} type="date" label={gettext("Order date")} required />
          <.input field={@form[:due_date]} type="date" label={gettext("Due date")} />
        </div>
        <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save order")}
          </.button>
          <.button navigate={cancel_path(@order)}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, :customer_options, customer_options())
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    order = %Order{order_date: Date.utc_today()}

    socket
    |> assign(:page_title, gettext("New order"))
    |> assign(:order, order)
    |> assign_form(Orders.change_order(order))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    order = Orders.get_order!(id)

    socket
    |> assign(:page_title, gettext("Edit order"))
    |> assign(:order, order)
    |> assign_form(Orders.change_order(order))
  end

  @impl true
  def handle_event("validate", %{"order" => params}, socket) do
    changeset = Orders.change_order(socket.assigns.order, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"order" => params}, socket) do
    save_order(socket, socket.assigns.live_action, params)
  end

  defp save_order(socket, :new, params) do
    case Orders.create_order(params) do
      {:ok, order} -> saved(socket, order, gettext("Order created."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_order(socket, :edit, params) do
    case Orders.update_order(socket.assigns.order, params) do
      {:ok, order} ->
        saved(socket, order, gettext("Order updated."))

      {:error, :not_editable} ->
        {:noreply, put_flash(socket, :error, gettext("This order can no longer be edited."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, order, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/orders/#{order}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "order"))
  end

  defp customer_options do
    CRM.list_relations(type: :customer) |> Enum.map(&{&1.name, &1.id})
  end

  defp cancel_path(%Order{id: nil}), do: ~p"/orders"
  defp cancel_path(order), do: ~p"/orders/#{order}"
end
