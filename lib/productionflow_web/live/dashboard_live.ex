defmodule ProductionflowWeb.DashboardLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.Dashboard
  import ProductionflowWeb.Orders.Badges, only: [status_label: 1, order_status_class: 1]

  @impl true
  def mount(_params, _session, socket) do
    summary = Dashboard.summary(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Dashboard"))
     |> assign(:summary, summary)
     |> assign(:alerts, alert_items(summary))
     |> assign(:kpis, kpi_items(summary))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Welcome back")}
        <:subtitle>{@current_scope.user.email}</:subtitle>
      </.header>

      <section class="rounded-xl border border-base-300 bg-base-100 p-5">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/50">
          {gettext("Needs attention")}
        </h2>
        <ul :if={@alerts != []} class="space-y-2">
          <li :for={alert <- @alerts}>
            <.link navigate={alert.path} class="flex items-center gap-3 hover:underline">
              <span class={["badge", "badge-#{alert.level}"]}>{alert.count}</span>
              <span class="text-sm">{alert.label}</span>
            </.link>
          </li>
        </ul>
        <p :if={@alerts == []} class="text-sm text-base-content/60">
          {gettext("Nothing needs attention right now.")}
        </p>
      </section>

      <section :if={@kpis != []} class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <.link
          :for={kpi <- @kpis}
          navigate={kpi.path}
          class="rounded-xl border border-base-300 bg-base-100 p-4 hover:bg-base-200"
        >
          <p class="text-xs text-base-content/50">{kpi.label}</p>
          <p class="mt-1 text-2xl font-semibold">{kpi.value}</p>
        </.link>
      </section>

      <section :if={@summary.recent != []} class="rounded-xl border border-base-300 bg-base-100 p-5">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/50">
          {gettext("Recent activity")}
        </h2>
        <ul class="divide-y divide-base-200">
          <li :for={order <- @summary.recent} class="flex items-center gap-3 py-2">
            <.link navigate={~p"/orders/#{order}"} class="flex-1 text-sm hover:underline">
              <span class="font-medium">{order.number || order.quote_number}</span>
              <span class="text-base-content/60">· {order.relation.name}</span>
            </.link>
            <span class={["badge badge-sm", order_status_class(order.status)]}>
              {status_label(order.status)}
            </span>
          </li>
        </ul>
      </section>

      <p
        :if={@alerts == [] and @kpis == [] and @summary.recent == []}
        class="text-sm text-base-content/60"
      >
        {gettext("You don't have access to any dashboard data yet.")}
      </p>
    </Layouts.app>
    """
  end

  # Alert rows: only metrics that are both visible (non-nil) and non-zero.
  defp alert_items(summary) do
    [
      {summary.overdue_orders, gettext("orders overdue"), "error", ~p"/orders"},
      {summary.low_stock, gettext("materials low on stock"), "warning", ~p"/inventory/materials"},
      {summary.unscheduled_steps, gettext("steps not yet scheduled"), "info", ~p"/planning"},
      {summary.late_steps, gettext("steps planned past their due date"), "error", ~p"/planning"}
    ]
    |> Enum.filter(fn {count, _, _, _} -> is_integer(count) and count > 0 end)
    |> Enum.map(fn {count, label, level, path} ->
      %{count: count, label: label, level: level, path: path}
    end)
  end

  # KPI cards: every metric the scope can see (shown even at zero).
  defp kpi_items(summary) do
    [
      {summary.open_quotes, gettext("Open quotes"), ~p"/quotes"},
      {summary.active_orders, gettext("Active orders"), ~p"/orders"},
      {summary.low_stock, gettext("Low stock"), ~p"/inventory/materials"},
      {summary.stock_value && money(summary.stock_value), gettext("Stock value"),
       ~p"/inventory/materials"},
      {summary.machines, gettext("Machines"), ~p"/production/machines"},
      {summary.customers, gettext("Customers"), ~p"/relations"}
    ]
    |> Enum.filter(fn {value, _, _} -> not is_nil(value) end)
    |> Enum.map(fn {value, label, path} -> %{value: value, label: label, path: path} end)
  end
end
