defmodule Productionflow.Catalog.ProductTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_templates" do
    field :name, :string
    field :sku, :string
    field :output_unit, :string
    field :description, :string
    field :margin_pct, :decimal
    field :archived_at, :utc_datetime

    has_many :route_steps, Productionflow.Catalog.RouteStep,
      preload_order: [asc: :position, asc: :id]

    has_many :materials, Productionflow.Catalog.TemplateMaterial

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product_template, attrs) do
    product_template
    |> cast(attrs, [:name, :sku, :output_unit, :description, :margin_pct])
    |> validate_required([:name, :output_unit])
    |> validate_length(:name, max: 160)
    |> validate_number(:margin_pct, greater_than_or_equal_to: 0)
    |> update_change(:sku, &blank_to_nil/1)
    |> unique_constraint(:sku, name: :product_templates_sku_index)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
