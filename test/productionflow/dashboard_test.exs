defmodule Productionflow.DashboardTest do
  use Productionflow.DataCase, async: true

  alias Productionflow.{Dashboard, Orders}
  alias Productionflow.Accounts.Scope

  import Productionflow.AccountsFixtures
  import Productionflow.OrdersFixtures
  import Productionflow.InventoryFixtures

  defp scope_with(permissions),
    do: Scope.for_user(user_fixture_with_permissions(permissions))

  test "hides every metric for a scope without permissions" do
    summary = Dashboard.summary(scope_with([]))

    assert summary.overdue_orders == nil
    assert summary.open_quotes == nil
    assert summary.active_orders == nil
    assert summary.low_stock == nil
    assert summary.stock_value == nil
    assert summary.machines == nil
    assert summary.customers == nil
    assert summary.recent == []
  end

  test "summarises orders for an orders.view scope, leaving other areas nil" do
    yesterday = Date.add(Date.utc_today(), -1)
    _draft = order_fixture()
    {:ok, _accepted} = Orders.accept_quote(order_fixture(nil, %{"due_date" => yesterday}))

    summary = Dashboard.summary(scope_with(["orders.view"]))

    assert summary.open_quotes == 1
    assert summary.active_orders == 1
    assert summary.overdue_orders == 1
    assert length(summary.recent) == 2

    # Areas the scope can't see stay nil.
    assert summary.low_stock == nil
    assert summary.machines == nil
  end

  test "summarises inventory for an inventory.view scope" do
    material_fixture(%{
      cost_price: "2",
      minimum_stock: "100",
      opening_stock: "10"
    })

    summary = Dashboard.summary(scope_with(["inventory.view"]))

    assert summary.low_stock == 1
    assert Decimal.equal?(summary.stock_value, Decimal.new("20"))
    assert summary.open_quotes == nil
  end
end
