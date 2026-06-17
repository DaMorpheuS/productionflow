defmodule Productionflow.Planning.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "planning_settings" do
    field :schedule_from, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    cast(settings, attrs, [:schedule_from])
  end
end
