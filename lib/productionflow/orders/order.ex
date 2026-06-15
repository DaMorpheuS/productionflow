defmodule Productionflow.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:draft, :confirmed, :in_production, :completed, :cancelled]

  # Legal status transitions. An order is cancellable from any non-terminal
  # state; `completed` and `cancelled` are terminal.
  @transitions %{
    draft: [:confirmed, :cancelled],
    confirmed: [:in_production, :cancelled],
    in_production: [:completed, :cancelled],
    completed: [],
    cancelled: []
  }

  schema "orders" do
    field :number, :string
    field :reference, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :order_date, :date
    field :due_date, :date
    field :notes, :string

    belongs_to :relation, Productionflow.CRM.Relation

    has_many :lines, Productionflow.Orders.OrderLine, preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  @doc "The status values."
  def statuses, do: @statuses

  @doc "The statuses reachable from `status`."
  def next_statuses(status), do: Map.get(@transitions, status, [])

  @doc "Changeset for the editable order fields (not number/status)."
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:relation_id, :reference, :order_date, :due_date, :notes])
    |> validate_required([:relation_id, :order_date])
    |> assoc_constraint(:relation)
    |> unique_constraint(:number)
  end

  @doc """
  Changeset that moves the order to `new_status`, rejecting transitions not
  allowed from the current status.
  """
  def transition_changeset(order, new_status) do
    change = change(order, status: new_status)

    if new_status in next_statuses(order.status) do
      change
    else
      add_error(change, :status, "cannot move from #{order.status} to #{new_status}")
    end
  end
end
