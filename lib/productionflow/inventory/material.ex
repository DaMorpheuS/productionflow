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
    field :attributes, :map, default: %{}

    belongs_to :supplier, Productionflow.CRM.Relation
    belongs_to :category, Productionflow.Inventory.Category
    belongs_to :material_type, Productionflow.Inventory.MaterialType
    has_many :movements, Productionflow.Inventory.StockMovement

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a material. `current_stock` is intentionally NOT cast — only the
  stock-movement ledger changes it.

  `field_definitions` are the field definitions of the material's (incoming)
  type; the custom `attributes` map is built and validated against them, pruning
  any value whose key is not defined by the current type.
  """
  def changeset(material, attrs, field_definitions \\ []) do
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
      :category_id,
      :material_type_id
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
    |> assoc_constraint(:material_type)
    |> unique_constraint(:sku, name: :materials_sku_index)
    |> put_attributes(attrs, field_definitions)
  end

  # Builds the cleaned `attributes` map by iterating the type's field
  # definitions (so unknown/old-type keys are dropped) and validating each value
  # by its field type. Errors are attached to `:attributes` keyed by field key.
  defp put_attributes(changeset, attrs, field_definitions) do
    incoming = attrs |> Map.get("attributes", Map.get(attrs, :attributes, %{})) |> normalize_map()

    {cleaned, errors} =
      Enum.reduce(field_definitions, {%{}, []}, fn definition, {acc, errs} ->
        raw = Map.get(incoming, definition.key)

        case coerce(definition, raw) do
          :drop -> {acc, errs}
          {:ok, value} -> {Map.put(acc, definition.key, value), errs}
          {:error, message} -> {acc, [{definition.key, message} | errs]}
        end
      end)

    changeset = put_change(changeset, :attributes, cleaned)

    Enum.reduce(errors, changeset, fn {key, message}, cs ->
      add_error(cs, :attributes, message, key: key)
    end)
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}

  # Coercion per field type. Returns {:ok, value} | :drop | {:error, message}.
  defp coerce(%{field_type: :boolean}, raw), do: {:ok, raw in [true, "true", "on"]}

  defp coerce(definition, raw) do
    trimmed = raw |> to_string() |> String.trim()

    cond do
      trimmed == "" and definition.required -> {:error, "is required"}
      trimmed == "" -> :drop
      true -> coerce_present(definition, trimmed)
    end
  end

  defp coerce_present(%{field_type: :number}, value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, Decimal.to_string(decimal)}
      _ -> {:error, "must be a number"}
    end
  end

  defp coerce_present(%{field_type: :select, options: options}, value) do
    if value in options, do: {:ok, value}, else: {:error, "is not a valid option"}
  end

  defp coerce_present(_definition, value), do: {:ok, value}

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
