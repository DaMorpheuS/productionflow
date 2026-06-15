defmodule Productionflow.OrdersFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.Orders` context.
  """

  alias Productionflow.Orders

  import Productionflow.CRMFixtures

  @doc "Creates a draft order for `relation` (a customer is created if omitted)."
  def order_fixture(relation \\ nil, attrs \\ %{}) do
    relation = relation || relation_fixture()
    {:ok, order} = Orders.create_order(Map.merge(%{"relation_id" => relation.id}, attrs))
    order
  end
end
