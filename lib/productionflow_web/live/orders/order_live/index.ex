defmodule ProductionflowWeb.Orders.OrderLive.Index do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.Orders
  alias Productionflow.Orders.Order
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Orders"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:statuses, Order.statuses())
     |> assign(:filter, %{"search" => "", "status" => ""})
     |> stream(:orders, Orders.list_orders())}
  end

  @impl true
  def handle_event("filter", %{"search" => _} = filter, socket) do
    orders =
      Orders.list_orders(
        search: filter["search"],
        status: parse_status(filter["status"])
      )

    {:noreply, socket |> assign(:filter, filter) |> stream(:orders, orders, reset: true)}
  end

  defp parse_status(""), do: nil
  defp parse_status(status), do: String.to_existing_atom(status)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Orders")}
        <:subtitle>{gettext("Customer production orders.")}</:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/orders/settings"}>
            {gettext("Numbering")}
          </.button>
          <.button :if={@can_manage} variant="primary" navigate={~p"/orders/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New order")}
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} phx-change="filter" id="order-filters" class="flex flex-wrap gap-3">
        <input
          type="text"
          name="search"
          value={@filter["search"]}
          placeholder={gettext("Search number, reference or customer")}
          phx-debounce="300"
          class="input"
        />
        <select name="status" class="select">
          <option value="">{gettext("All statuses")}</option>
          <option :for={s <- @statuses} value={s} selected={@filter["status"] == to_string(s)}>
            {status_label(s)}
          </option>
        </select>
      </.form>

      <.table id="orders" rows={@streams.orders}>
        <:col :let={{_id, order}} label={gettext("Number")}>
          <.link navigate={~p"/orders/#{order}"} class="font-semibold hover:underline">
            {order.number}
          </.link>
        </:col>
        <:col :let={{_id, order}} label={gettext("Customer")}>{order.relation.name}</:col>
        <:col :let={{_id, order}} label={gettext("Reference")}>{order.reference}</:col>
        <:col :let={{_id, order}} label={gettext("Status")}>
          <span class={["badge", order_status_class(order.status)]}>
            {status_label(order.status)}
          </span>
        </:col>
        <:col :let={{_id, order}} label={gettext("Date")}>{order.order_date}</:col>
        <:action :let={{_id, order}}>
          <.link navigate={~p"/orders/#{order}"}>{gettext("View")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
