defmodule Productionflow.Production.Machine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "machines" do
    field :name, :string
    field :output_unit, :string
    field :units_per_hour, :decimal
    field :setup_minutes, :decimal, default: Decimal.new(0)
    field :power_kw, :decimal, default: Decimal.new(0)
    field :purchase_price, :decimal, default: Decimal.new(0)
    field :residual_value, :decimal, default: Decimal.new(0)
    field :yearly_maintenance_cost, :decimal, default: Decimal.new(0)
    field :lifetime_years, :decimal
    field :productive_hours_per_year, :decimal
    field :archived_at, :utc_datetime

    has_many :time_modifiers, Productionflow.Production.TimeModifier

    many_to_many :operators, Productionflow.Accounts.User,
      join_through: "machine_operators",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :name,
    :output_unit,
    :units_per_hour,
    :setup_minutes,
    :power_kw,
    :purchase_price,
    :residual_value,
    :yearly_maintenance_cost,
    :lifetime_years,
    :productive_hours_per_year
  ]

  @doc """
  Builds a machine changeset.

  Operators are an association resolved by the context (user-chosen ids → `User`
  structs) and applied with `put_assoc`; pass them as the third argument. `nil`
  leaves the current operators untouched.
  """
  def changeset(machine, attrs, operators \\ nil) do
    machine
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :output_unit, :units_per_hour])
    |> validate_number(:units_per_hour, greater_than: 0)
    |> validate_number(:setup_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:power_kw, greater_than_or_equal_to: 0)
    |> validate_number(:lifetime_years, greater_than: 0)
    |> validate_number(:productive_hours_per_year, greater_than: 0)
    |> maybe_put_operators(operators)
  end

  defp maybe_put_operators(changeset, nil), do: changeset
  defp maybe_put_operators(changeset, operators), do: put_assoc(changeset, :operators, operators)
end
