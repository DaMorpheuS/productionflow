defmodule Productionflow.Orders.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @number_modes [:per_year, :continuous]

  schema "order_settings" do
    field :number_mode, Ecto.Enum, values: @number_modes, default: :per_year
    field :number_prefix, :string, default: "ORD"
    field :quote_number_mode, Ecto.Enum, values: @number_modes, default: :per_year
    field :quote_number_prefix, :string, default: "QUO"

    timestamps(type: :utc_datetime)
  end

  @doc "The supported numbering modes."
  def number_modes, do: @number_modes

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:number_mode, :number_prefix, :quote_number_mode, :quote_number_prefix])
    |> validate_required([
      :number_mode,
      :number_prefix,
      :quote_number_mode,
      :quote_number_prefix
    ])
    |> validate_length(:number_prefix, min: 1, max: 12)
    |> validate_length(:quote_number_prefix, min: 1, max: 12)
  end
end
