defmodule ProductionflowWeb.Orders.OrderLive.Index do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.Orders
  alias Productionflow.Orders.Order
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = if socket.assigns.live_action == :quotes, do: :quotes, else: :orders

    {:ok,
     socket
     |> assign(:scope, scope)
     |> assign(:page_title, if(scope == :quotes, do: gettext("Quotes"), else: gettext("Orders")))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:statuses, scope_statuses(scope))
     |> assign(:filter, %{"search" => "", "status" => "", "include_archived" => "false"})
     |> load(scope, %{"search" => "", "status" => "", "include_archived" => "false"})}
  end

  defp load(socket, scope, filter) do
    orders =
      Orders.list_orders(
        scope: scope,
        search: filter["search"],
        status: parse_status(filter["status"]),
        include_archived: filter["include_archived"] == "true"
      )

    stream(socket, :orders, orders, reset: true)
  end

  @impl true
  def handle_event("filter", %{"search" => _} = filter, socket) do
    {:noreply, socket |> assign(:filter, filter) |> load(socket.assigns.scope, filter)}
  end

  defp parse_status(""), do: nil
  defp parse_status(status), do: String.to_existing_atom(status)

  defp scope_statuses(:quotes), do: Order.quote_statuses()
  defp scope_statuses(:orders), do: Order.statuses() -- Order.quote_statuses()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>
          {if @scope == :quotes,
            do: gettext("Customer quotes awaiting a decision."),
            else: gettext("Accepted jobs in production.")}
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/orders/settings"}>
            {gettext("Numbering")}
          </.button>
          <.button :if={@can_manage} variant="primary" navigate={~p"/orders/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New quote")}
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
        <label class="flex items-center gap-2 text-sm">
          <input type="hidden" name="include_archived" value="false" />
          <input
            type="checkbox"
            name="include_archived"
            value="true"
            checked={@filter["include_archived"] == "true"}
            class="checkbox checkbox-sm"
          /> {gettext("Show archived")}
        </label>
      </.form>

      <.table id="orders" rows={@streams.orders}>
        <:col :let={{_id, order}} label={gettext("Number")}>
          <.link navigate={~p"/orders/#{order}"} class="font-semibold hover:underline">
            {order.number || order.quote_number}
          </.link>
          <span :if={order.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
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
