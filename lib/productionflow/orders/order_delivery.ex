defmodule Productionflow.Orders.OrderDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_deliveries" do
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

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:address_id, :street, :postal_code, :city, :country, :planned_date])
    |> validate_required([:street, :city])
  end
end
