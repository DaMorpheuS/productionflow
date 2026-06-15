defmodule Productionflow.InventoryFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.Inventory` context.
  """

  alias Productionflow.Inventory

  def category_fixture(attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{name: "Category #{System.unique_integer([:positive])}"})
      |> Inventory.create_category()

    category
  end

  def material_fixture(attrs \\ %{}) do
    {:ok, material} =
      attrs
      |> Enum.into(%{
        name: "Material #{System.unique_integer([:positive])}",
        unit: "pieces"
      })
      |> Inventory.create_material()

    material
  end
end
