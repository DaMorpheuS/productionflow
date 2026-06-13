defmodule Productionflow.CRM.Address do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:invoice, :delivery, :visiting]

  schema "addresses" do
    field :kind, Ecto.Enum, values: @kinds, default: :delivery
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :country, :string
    field :is_default, :boolean, default: false

    belongs_to :relation, Productionflow.CRM.Relation
    has_many :contacts, Productionflow.CRM.Contact

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the list of valid address kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [:kind, :street, :postal_code, :city, :country, :is_default])
    |> validate_required([:kind, :street, :city])
  end
end
