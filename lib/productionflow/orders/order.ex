defmodule Productionflow.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:draft, :sent, :accepted, :declined, :in_production, :completed, :cancelled]

  @quote_statuses [:draft, :sent, :declined]

  @decline_reasons [:price, :technical, :other]

  # Legal status transitions. A document is a quote until it is accepted, then an
  # order. A quote can be sent, accepted, declined or revised back to draft;
  # accepting turns it into an order. `completed`/`cancelled` are terminal.
  @transitions %{
    draft: [:sent, :accepted, :cancelled],
    sent: [:accepted, :declined, :draft],
    declined: [:draft],
    accepted: [:in_production, :cancelled],
    in_production: [:completed, :cancelled],
    completed: [],
    cancelled: []
  }

  schema "orders" do
    field :quote_number, :string
    field :number, :string
    field :reference, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :order_date, :date
    field :due_date, :date
    field :valid_until, :date
    field :notes, :string

    field :decline_reason, Ecto.Enum, values: @decline_reasons
    field :decline_notes, :string

    field :archived_at, :utc_datetime
    field :archive_reason, :string

    belongs_to :relation, Productionflow.CRM.Relation

    has_many :lines, Productionflow.Orders.OrderLine, preload_order: [asc: :position, asc: :id]

    has_many :deliveries, Productionflow.Orders.OrderDelivery,
      preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  @doc "The status values."
  def statuses, do: @statuses

  @doc "The statuses a document has while it is still a quote."
  def quote_statuses, do: @quote_statuses

  @doc "The decline-reason values."
  def decline_reasons, do: @decline_reasons

  @doc "Whether the document is still a quote (not yet accepted)."
  def quote?(%__MODULE__{status: status}), do: status in @quote_statuses

  @doc "Whether the document has become an order (accepted or beyond)."
  def order?(%__MODULE__{} = order), do: not quote?(order)

  @doc "Whether the header, lines and deliveries can still be edited."
  def editable?(%__MODULE__{status: status}), do: status in [:draft, :accepted]

  @doc "The statuses reachable from `status`."
  def next_statuses(status), do: Map.get(@transitions, status, [])

  @doc "Changeset for the editable order fields (not numbers/status)."
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:relation_id, :reference, :order_date, :due_date, :valid_until, :notes])
    |> validate_required([:relation_id, :order_date])
    |> assoc_constraint(:relation)
    |> unique_constraint(:quote_number)
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
