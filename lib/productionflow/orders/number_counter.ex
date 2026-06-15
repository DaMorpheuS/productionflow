defmodule Productionflow.Orders.NumberCounter do
  @moduledoc """
  Per-scope monotonic counter backing order numbering. `scope` is a year
  (`"2026"`) for per-year numbering or `"global"` for a continuous sequence.
  """

  use Ecto.Schema

  schema "order_number_counters" do
    field :scope, :string
    field :value, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
