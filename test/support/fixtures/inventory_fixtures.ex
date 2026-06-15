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

  def material_type_fixture(attrs \\ %{}) do
    {:ok, type} =
      attrs
      |> Enum.into(%{name: "Type #{System.unique_integer([:positive])}"})
      |> Inventory.create_material_type()

    type
  end

  def field_definition_fixture(type, attrs \\ %{}) do
    {:ok, definition} =
      Inventory.create_field_definition(
        type,
        Enum.into(attrs, %{
          key: "field_#{System.unique_integer([:positive])}",
          label: "Field",
          field_type: :text
        })
      )

    definition
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
