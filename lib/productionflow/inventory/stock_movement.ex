defmodule Productionflow.Inventory.StockMovement do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:purchase, :consumption, :adjustment]

  schema "stock_movements" do
    field :kind, Ecto.Enum, values: @kinds
    field :quantity, :decimal
    field :unit_cost, :decimal
    field :note, :string

    belongs_to :material, Productionflow.Inventory.Material
    belongs_to :user, Productionflow.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the valid movement kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(movement, attrs) do
    movement
    |> cast(attrs, [:kind, :quantity, :unit_cost, :note])
    |> validate_required([:kind, :quantity])
  end
end
