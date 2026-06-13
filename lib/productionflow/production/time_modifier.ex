defmodule Productionflow.Production.TimeModifier do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:percentage, :fixed_minutes]

  schema "time_modifiers" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds, default: :percentage
    field :value, :decimal

    belongs_to :machine, Productionflow.Production.Machine

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the valid modifier kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(time_modifier, attrs) do
    time_modifier
    |> cast(attrs, [:name, :kind, :value])
    |> validate_required([:name, :kind, :value])
    |> validate_number(:value, greater_than_or_equal_to: 0)
  end
end
