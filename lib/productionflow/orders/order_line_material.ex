defmodule Productionflow.Orders.OrderLineMaterial do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_line_materials" do
    field :material_name, :string
    field :unit, :string
    field :quantity, :decimal
    field :unit_cost, :decimal
    field :cost, :decimal
    field :consumed_at, :utc_datetime

    belongs_to :order_line, Productionflow.Orders.OrderLine
    belongs_to :material, Productionflow.Inventory.Material

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(line_material, attrs) do
    line_material
    |> cast(attrs, [:material_id, :quantity])
    |> validate_required([:material_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> assoc_constraint(:material)
  end
end
