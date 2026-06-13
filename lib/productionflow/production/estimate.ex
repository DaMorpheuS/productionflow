defmodule Productionflow.Production.Estimate do
  @moduledoc """
  A non-persisted result of estimating a job on a machine: the duration and the
  internal-cost breakdown for a given quantity. All amounts are `Decimal`;
  `machine_cost` is `nil` when the machine's cost basis is incomplete.
  """

  defstruct [:duration_minutes, :machine_cost, :labour_cost, :energy_cost, :total_cost]
end
