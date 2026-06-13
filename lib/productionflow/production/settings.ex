defmodule Productionflow.Production.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "production_settings" do
    field :energy_price_per_kwh, :decimal, default: Decimal.new(0)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:energy_price_per_kwh])
    |> validate_required([:energy_price_per_kwh])
    |> validate_number(:energy_price_per_kwh, greater_than_or_equal_to: 0)
  end
end
