defmodule Productionflow.Catalog.CostEstimate do
  @moduledoc """
  Non-persisted result of estimating a product template at a quantity: total
  duration and the internal-cost breakdown (machine + labour + energy +
  materials), plus per-step and per-material line detail.

  `machine_cost`, `total_cost` and `unit_cost` are `nil` when any step's machine
  has an incomplete cost basis (see `Productionflow.Production.estimate/3`).
  """

  defstruct duration_minutes: Decimal.new(0),
            machine_cost: Decimal.new(0),
            labour_cost: Decimal.new(0),
            energy_cost: Decimal.new(0),
            material_cost: Decimal.new(0),
            total_cost: Decimal.new(0),
            unit_cost: nil,
            steps: [],
            materials: []
end
