defmodule Productionflow.Inventory.FieldDefinition do
  use Ecto.Schema
  import Ecto.Changeset

  @field_types [:text, :number, :boolean, :select]

  schema "field_definitions" do
    field :key, :string
    field :label, :string
    field :field_type, Ecto.Enum, values: @field_types, default: :text
    field :unit, :string
    field :options, {:array, :string}, default: []
    field :required, :boolean, default: false
    field :default_value, :string
    field :position, :integer, default: 0

    belongs_to :material_type, Productionflow.Inventory.MaterialType

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the valid field types."
  def field_types, do: @field_types

  @doc false
  def changeset(field_definition, attrs) do
    field_definition
    |> cast(split_options(attrs), [
      :key,
      :label,
      :field_type,
      :unit,
      :options,
      :required,
      :default_value,
      :position
    ])
    |> normalize_options()
    |> validate_required([:key, :label, :field_type])
    |> validate_format(:key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must start with a letter and use only lowercase letters, numbers and underscores"
    )
    |> validate_length(:key, max: 60)
    |> validate_select_options()
    |> unique_constraint(:key,
      name: :field_definitions_material_type_id_key_index,
      message: "is already used in this type"
    )
  end

  # The form submits options as one comma-separated string; turn it into a list
  # before casting the `{:array, :string}` field.
  defp split_options(attrs) do
    cond do
      is_binary(attrs["options"]) ->
        Map.put(attrs, "options", String.split(attrs["options"], ","))

      is_binary(attrs[:options]) ->
        Map.put(attrs, :options, String.split(attrs[:options], ","))

      true ->
        attrs
    end
  end

  # Trim and drop blanks/duplicates from the options list.
  defp normalize_options(changeset) do
    case get_change(changeset, :options) do
      nil -> changeset
      options -> put_change(changeset, :options, clean_options(options))
    end
  end

  defp clean_options(options) do
    options |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
  end

  defp validate_select_options(changeset) do
    if get_field(changeset, :field_type) == :select and get_field(changeset, :options) == [] do
      add_error(changeset, :options, "add at least one option for a dropdown field")
    else
      changeset
    end
  end
end
