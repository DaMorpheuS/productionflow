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
    field :working_day_start, :time, default: ~T[08:00:00]
    field :working_day_end, :time, default: ~T[16:30:00]
    field :working_days, {:array, :integer}, default: [1, 2, 3, 4, 5]
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
    :productive_hours_per_year,
    :working_day_start,
    :working_day_end,
    :working_days
  ]

  @doc """
  Builds a machine changeset.

  Operators are an association resolved by the context (user-chosen ids → `User`
  structs) and applied with `put_assoc`; pass them as the third argument. `nil`
  leaves the current operators untouched.
  """
  def changeset(machine, attrs, operators \\ nil) do
    machine
    |> cast(clean_working_days(attrs), @cast_fields)
    |> validate_required([:name, :output_unit, :units_per_hour])
    |> validate_number(:units_per_hour, greater_than: 0)
    |> validate_number(:setup_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:power_kw, greater_than_or_equal_to: 0)
    |> validate_number(:lifetime_years, greater_than: 0)
    |> validate_number(:productive_hours_per_year, greater_than: 0)
    |> validate_required([:working_day_start, :working_day_end, :working_days])
    |> validate_length(:working_days, min: 1)
    |> validate_subset(:working_days, Enum.to_list(1..7))
    |> validate_working_hours()
    |> maybe_put_operators(operators)
  end

  # Working-day checkboxes arrive as a list of strings with a leading "" from the
  # hidden input; strip the blank and cast to integers before Ecto's array cast,
  # which can't coerce "" to an integer.
  defp clean_working_days(%{"working_days" => days} = attrs) when is_list(days),
    do: %{attrs | "working_days" => clean_days(days)}

  defp clean_working_days(%{working_days: days} = attrs) when is_list(days),
    do: %{attrs | working_days: clean_days(days)}

  defp clean_working_days(attrs), do: attrs

  defp clean_days(days) do
    days
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(fn
      day when is_integer(day) -> day
      day when is_binary(day) -> String.to_integer(day)
    end)
  end

  defp validate_working_hours(changeset) do
    start = get_field(changeset, :working_day_start)
    finish = get_field(changeset, :working_day_end)

    if start && finish && Time.compare(finish, start) != :gt do
      add_error(changeset, :working_day_end, "must be after the start time")
    else
      changeset
    end
  end

  defp maybe_put_operators(changeset, nil), do: changeset
  defp maybe_put_operators(changeset, operators), do: put_assoc(changeset, :operators, operators)
end
