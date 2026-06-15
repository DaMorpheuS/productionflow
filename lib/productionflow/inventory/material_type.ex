defmodule Productionflow.Inventory.MaterialType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "material_types" do
    field :name, :string

    has_many :field_definitions, Productionflow.Inventory.FieldDefinition,
      preload_order: [asc: :position, asc: :id]

    has_many :materials, Productionflow.Inventory.Material

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(material_type, attrs) do
    material_type
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name)
  end
end
