defmodule Productionflow.Pricing.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pricing_settings" do
    field :default_margin_pct, :decimal, default: Decimal.new(0)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:default_margin_pct])
    |> validate_required([:default_margin_pct])
    |> validate_number(:default_margin_pct, greater_than_or_equal_to: 0)
  end
end
