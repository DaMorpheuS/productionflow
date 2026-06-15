defmodule Productionflow.CatalogFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.Catalog` context.
  """

  alias Productionflow.Catalog

  def product_template_fixture(attrs \\ %{}) do
    {:ok, template} =
      attrs
      |> Enum.into(%{
        name: "Product #{System.unique_integer([:positive])}",
        output_unit: "item"
      })
      |> Catalog.create_product_template()

    template
  end

  def route_step_fixture(template, machine, attrs \\ %{}) do
    {:ok, step} =
      Catalog.add_route_step(
        template,
        Enum.into(attrs, %{machine_id: machine.id, quantity_per_unit: Decimal.new(1)})
      )

    step
  end

  def template_material_fixture(template, material, attrs \\ %{}) do
    {:ok, line} =
      Catalog.add_template_material(
        template,
        Enum.into(attrs, %{material_id: material.id, quantity_per_unit: Decimal.new(1)})
      )

    line
  end
end
