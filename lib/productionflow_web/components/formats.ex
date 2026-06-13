defmodule ProductionflowWeb.Formats do
  @moduledoc """
  Small display formatters shared across templates: money and durations.

  These round only at display time; `nil` renders as an em dash so incomplete
  data reads honestly rather than as `€0.00`.
  """

  @dash "—"

  @doc ~S"""
  Formats a `Decimal`/number as a euro amount with two decimals.

      iex> ProductionflowWeb.Formats.money(Decimal.new("4.5"))
      "€4.50"
      iex> ProductionflowWeb.Formats.money(nil)
      "—"
  """
  def money(nil), do: @dash

  def money(%Decimal{} = amount) do
    "€" <> Decimal.to_string(Decimal.round(amount, 2), :normal)
  end

  def money(amount) when is_number(amount), do: money(Decimal.new(to_string(amount)))

  @doc ~S"""
  Formats a duration in minutes as `"Xh Ym"` (or `"Ym"` under an hour).

      iex> ProductionflowWeb.Formats.duration(Decimal.new("85"))
      "1h 25m"
      iex> ProductionflowWeb.Formats.duration(nil)
      "—"
  """
  def duration(nil), do: @dash

  def duration(%Decimal{} = minutes) do
    total = minutes |> Decimal.round(0) |> Decimal.to_integer()
    duration(total)
  end

  def duration(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 and mins > 0 -> "#{hours}h #{mins}m"
      hours > 0 -> "#{hours}h"
      true -> "#{mins}m"
    end
  end
end
