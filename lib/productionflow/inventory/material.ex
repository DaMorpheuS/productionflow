defmodule Productionflow.Inventory.Material do
  use Ecto.Schema
  import Ecto.Changeset

  schema "materials" do
    field :name, :string
    field :sku, :string
    field :supplier_code, :string
    field :unit, :string
    field :cost_price, :decimal, default: Decimal.new(0)
    field :sales_price, :decimal, default: Decimal.new(0)
    field :current_stock, :decimal, default: Decimal.new(0)
    field :minimum_stock, :decimal
    field :archived_at, :utc_datetime

    belongs_to :supplier, Productionflow.CRM.Relation
    belongs_to :category, Productionflow.Inventory.Category
    has_many :movements, Productionflow.Inventory.StockMovement

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a material. `current_stock` is intentionally NOT cast — only the
  stock-movement ledger changes it.
  """
  def changeset(material, attrs) do
    material
    |> cast(attrs, [
      :name,
      :sku,
      :supplier_code,
      :unit,
      :cost_price,
      :sales_price,
      :minimum_stock,
      :supplier_id,
      :category_id
    ])
    |> validate_required([:name, :unit])
    |> validate_length(:name, max: 160)
    |> update_change(:sku, &blank_to_nil/1)
    |> update_change(:supplier_code, &blank_to_nil/1)
    |> validate_number(:cost_price, greater_than_or_equal_to: 0)
    |> validate_number(:sales_price, greater_than_or_equal_to: 0)
    |> validate_number(:minimum_stock, greater_than_or_equal_to: 0)
    |> assoc_constraint(:supplier)
    |> assoc_constraint(:category)
    |> unique_constraint(:sku, name: :materials_sku_index)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
