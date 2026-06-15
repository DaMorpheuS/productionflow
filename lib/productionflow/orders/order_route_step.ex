defmodule Productionflow.Orders.OrderRouteStep do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :in_progress, :done]

  @transitions %{
    pending: [:in_progress],
    in_progress: [:done, :pending],
    done: [:in_progress]
  }

  schema "order_route_steps" do
    field :machine_name, :string
    field :position, :integer, default: 0
    field :quantity_per_unit, :decimal, default: Decimal.new(1)
    field :machine_quantity, :decimal
    field :duration_minutes, :decimal
    field :machine_cost, :decimal
    field :labour_cost, :decimal
    field :energy_cost, :decimal
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :order_line, Productionflow.Orders.OrderLine
    belongs_to :machine, Productionflow.Production.Machine

    timestamps(type: :utc_datetime)
  end

  @doc "The status values."
  def statuses, do: @statuses

  @doc "The statuses reachable from `status`."
  def next_statuses(status), do: Map.get(@transitions, status, [])

  @doc false
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:machine_id, :quantity_per_unit])
    |> validate_required([:machine_id, :quantity_per_unit])
    |> validate_number(:quantity_per_unit, greater_than: 0)
    |> assoc_constraint(:machine)
  end

  @doc """
  Changeset for an ad-hoc step: the user picks a machine and the total quantity
  it processes for the line (`machine_quantity`), from which time/cost are
  derived in the context.
  """
  def ad_hoc_changeset(step, attrs) do
    step
    |> cast(attrs, [:machine_id, :machine_quantity])
    |> validate_required([:machine_id, :machine_quantity])
    |> validate_number(:machine_quantity, greater_than: 0)
    |> assoc_constraint(:machine)
  end

  @doc "Changeset moving the step to `new_status`, rejecting illegal transitions."
  def transition_changeset(step, new_status) do
    change = change(step, status: new_status)

    if new_status in next_statuses(step.status) do
      change
    else
      add_error(change, :status, "cannot move from #{step.status} to #{new_status}")
    end
  end
end
