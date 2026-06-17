defmodule Productionflow.PlanningFixtures do
  @moduledoc """
  Test helpers for the `Productionflow.Planning` context.
  """

  alias Productionflow.Orders

  import Productionflow.OrdersFixtures

  @doc """
  Builds an accepted order with one ad-hoc line carrying a single route step on
  `machine` processing `machine_quantity` units, and returns the reloaded step.

  ## Options
    * `:machine_quantity` - units the step processes (default 60)
    * `:due_date` - the order's due date
  """
  def route_step_fixture(machine, opts \\ []) do
    quantity = Keyword.get(opts, :machine_quantity, 60)

    attrs =
      case Keyword.get(opts, :due_date) do
        nil -> %{}
        date -> %{"due_date" => Date.to_iso8601(date)}
      end

    order = order_fixture(nil, attrs)
    {:ok, line} = Orders.add_blank_line(order, %{"description" => "Line", "quantity" => "1"})

    {:ok, _line} =
      Orders.add_line_route_step(line, %{
        "machine_id" => machine.id,
        "machine_quantity" => to_string(quantity)
      })

    {:ok, _order} = Orders.accept_quote(order)

    Orders.get_line!(line.id).route_steps |> List.last()
  end
end
