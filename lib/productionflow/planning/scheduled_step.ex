defmodule Productionflow.Planning.ScheduledStep do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scheduled_steps" do
    field :position, :integer, default: 0
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    belongs_to :order_route_step, Productionflow.Orders.OrderRouteStep
    belongs_to :machine, Productionflow.Production.Machine

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(scheduled_step, attrs) do
    scheduled_step
    |> cast(attrs, [:order_route_step_id, :machine_id, :position, :starts_at, :ends_at])
    |> validate_required([:order_route_step_id, :machine_id])
    |> unique_constraint(:order_route_step_id)
    |> assoc_constraint(:order_route_step)
    |> assoc_constraint(:machine)
  end
end
