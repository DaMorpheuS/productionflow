defmodule Productionflow.Catalog.RouteStep do
  use Ecto.Schema
  import Ecto.Changeset

  schema "route_steps" do
    field :position, :integer, default: 0
    field :quantity_per_unit, :decimal, default: Decimal.new(1)
    field :time_modifier_ids, {:array, :integer}, default: []

    belongs_to :product_template, Productionflow.Catalog.ProductTemplate
    belongs_to :machine, Productionflow.Production.Machine

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(route_step, attrs) do
    route_step
    |> cast(normalize_modifier_ids(attrs), [
      :machine_id,
      :quantity_per_unit,
      :time_modifier_ids
    ])
    |> validate_required([:machine_id, :quantity_per_unit])
    |> validate_number(:quantity_per_unit, greater_than: 0)
    |> assoc_constraint(:machine)
  end

  # The checkbox group submits time_modifier_ids as strings with a leading ""
  # sentinel; turn it into a clean integer list before casting the array field
  # (Ecto can't cast "" to an integer).
  defp normalize_modifier_ids(attrs) do
    cond do
      Map.has_key?(attrs, "time_modifier_ids") ->
        Map.put(attrs, "time_modifier_ids", to_int_ids(attrs["time_modifier_ids"]))

      Map.has_key?(attrs, :time_modifier_ids) ->
        Map.put(attrs, :time_modifier_ids, to_int_ids(attrs[:time_modifier_ids]))

      true ->
        attrs
    end
  end

  defp to_int_ids(ids) when is_list(ids) do
    ids
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(fn
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
    end)
    |> Enum.uniq()
  end

  defp to_int_ids(_), do: []
end
