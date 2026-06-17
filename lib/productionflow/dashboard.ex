defmodule Productionflow.Dashboard do
  @moduledoc """
  Read-only aggregation for the overview dashboard.

  `summary/1` composes counts from the other contexts into a flat metrics map,
  computing only the metrics the given scope is allowed to see — a metric the
  user lacks permission for comes back as `nil` (so nothing leaks and no needless
  queries run). Presentation (labels, links, badges) is the web layer's job.
  """

  alias Productionflow.{Orders, Inventory, Production, CRM, Planning}
  alias Productionflow.Accounts.Scope

  @doc "Returns the dashboard metrics visible to `scope`."
  def summary(%Scope{} = scope) do
    order_counts = when_can(scope, "orders.view", &Orders.count_by_status/0)

    %{
      # Alerts (things needing attention)
      overdue_orders: when_can(scope, "orders.view", &Orders.count_overdue/0),
      low_stock: when_can(scope, "inventory.view", &Inventory.count_low_stock/0),
      unscheduled_steps: when_can(scope, "planning.view", &Planning.count_unscheduled/0),
      late_steps: when_can(scope, "planning.view", &Planning.count_late/0),

      # KPIs (status at a glance)
      open_quotes: order_counts && count_of(order_counts, [:draft, :sent]),
      active_orders: order_counts && count_of(order_counts, [:accepted, :in_production]),
      stock_value: when_can(scope, "inventory.view", &Inventory.total_stock_value/0),
      machines: when_can(scope, "production.view", &Production.count_machines/0),
      customers: when_can(scope, "crm.view", fn -> CRM.count_by_type().customer end),

      # Recent activity
      recent: if(Scope.can?(scope, "orders.view"), do: Orders.recent_activity(), else: [])
    }
  end

  defp when_can(scope, permission, fun) do
    if Scope.can?(scope, permission), do: fun.()
  end

  defp count_of(counts, statuses) do
    Enum.reduce(statuses, 0, fn status, acc -> acc + Map.get(counts, status, 0) end)
  end
end
