defmodule Productionflow.Catalog.TemplateMaterial do
  use Ecto.Schema
  import Ecto.Changeset

  schema "template_materials" do
    field :quantity_per_unit, :decimal
    field :waste_pct, :decimal, default: Decimal.new(0)

    belongs_to :product_template, Productionflow.Catalog.ProductTemplate
    belongs_to :material, Productionflow.Inventory.Material

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(template_material, attrs) do
    template_material
    |> cast(attrs, [:material_id, :quantity_per_unit, :waste_pct])
    |> validate_required([:material_id, :quantity_per_unit])
    |> validate_number(:quantity_per_unit, greater_than: 0)
    |> validate_number(:waste_pct, greater_than_or_equal_to: 0)
    |> assoc_constraint(:material)
  end
end
