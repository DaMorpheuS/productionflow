defmodule Productionflow.Orders.OrderDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:address, :pickup]

  schema "order_deliveries" do
    field :kind, Ecto.Enum, values: @kinds, default: :address
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :country, :string
    field :planned_date, :date
    field :position, :integer, default: 0

    belongs_to :order, Productionflow.Orders.Order
    belongs_to :address, Productionflow.CRM.Address

    has_many :items, Productionflow.Orders.OrderDeliveryItem, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc "The delivery kinds."
  def kinds, do: @kinds

  @doc "Whether this delivery is a customer pickup (no address)."
  def pickup?(%__MODULE__{kind: :pickup}), do: true
  def pickup?(%__MODULE__{}), do: false

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:kind, :address_id, :street, :postal_code, :city, :country, :planned_date])
    |> validate_required([:kind])
    |> validate_address()
  end

  # A delivery to an address needs a street + city; a pickup needs neither.
  defp validate_address(changeset) do
    if get_field(changeset, :kind) == :address do
      validate_required(changeset, [:street, :city])
    else
      changeset
    end
  end
end
