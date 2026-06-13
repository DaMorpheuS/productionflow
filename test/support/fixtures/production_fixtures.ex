defmodule Productionflow.ProductionFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.Production` context.
  """

  alias Productionflow.Production

  def machine_fixture(attrs \\ %{}, operator_ids \\ []) do
    {:ok, machine} =
      attrs
      |> Enum.into(%{
        name: "Machine #{System.unique_integer([:positive])}",
        output_unit: "pieces",
        units_per_hour: Decimal.new(60)
      })
      |> Production.create_machine(operator_ids)

    machine
  end

  def time_modifier_fixture(machine, attrs \\ %{}) do
    {:ok, modifier} =
      Production.add_time_modifier(
        machine,
        Enum.into(attrs, %{name: "Modifier", kind: :percentage, value: Decimal.new(10)})
      )

    modifier
  end

  def set_energy_price(price) do
    {:ok, settings} = Production.update_settings(%{energy_price_per_kwh: price})
    settings
  end
end
