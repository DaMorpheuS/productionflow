defmodule Productionflow.Orders.OrderDeliveryItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_delivery_items" do
    field :quantity, :decimal, default: Decimal.new(0)

    belongs_to :order_delivery, Productionflow.Orders.OrderDelivery
    belongs_to :order_line, Productionflow.Orders.OrderLine

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:quantity])
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
  end
end
