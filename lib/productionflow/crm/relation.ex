defmodule Productionflow.CRM.Relation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "relations" do
    field :name, :string
    field :code, :string
    field :is_customer, :boolean, default: false
    field :is_supplier, :boolean, default: false
    field :is_prospect, :boolean, default: false
    field :email, :string
    field :phone, :string
    field :website, :string
    field :vat_number, :string
    field :iban, :string
    field :remarks, :string
    field :archived_at, :utc_datetime

    has_many :addresses, Productionflow.CRM.Address
    has_many :contacts, Productionflow.CRM.Contact
    has_many :notes, Productionflow.CRM.Note

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(relation, attrs) do
    relation
    |> cast(attrs, [
      :name,
      :code,
      :is_customer,
      :is_supplier,
      :is_prospect,
      :email,
      :phone,
      :website,
      :vat_number,
      :iban,
      :remarks
    ])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> update_change(:code, &blank_to_nil/1)
    |> validate_at_least_one_type()
    |> unique_constraint(:code, name: :relations_code_index)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp validate_at_least_one_type(changeset) do
    customer = get_field(changeset, :is_customer)
    supplier = get_field(changeset, :is_supplier)
    prospect = get_field(changeset, :is_prospect)

    if customer || supplier || prospect do
      changeset
    else
      add_error(changeset, :is_customer, "select at least one type")
    end
  end
end
