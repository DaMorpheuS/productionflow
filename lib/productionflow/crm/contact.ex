defmodule Productionflow.CRM.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :name, :string
    field :job_title, :string
    field :email, :string
    field :phone, :string
    field :remarks, :string

    belongs_to :relation, Productionflow.CRM.Relation
    belongs_to :address, Productionflow.CRM.Address

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a contact changeset.

  `address_id` is user-chosen (the location dropdown), so it is cast — but it
  must reference an address of the parent relation. Pass the relation's address
  ids via `opts[:address_ids]` so the changeset can reject a foreign location.
  """
  def changeset(contact, attrs, opts \\ []) do
    contact
    |> cast(attrs, [:name, :job_title, :email, :phone, :remarks, :address_id])
    |> validate_required([:name])
    |> validate_address_belongs_to_relation(Keyword.get(opts, :address_ids, []))
    |> foreign_key_constraint(:address_id)
  end

  defp validate_address_belongs_to_relation(changeset, address_ids) do
    case get_field(changeset, :address_id) do
      nil ->
        changeset

      id ->
        if id in address_ids, do: changeset, else: add_error(changeset, :address_id, "is invalid")
    end
  end
end
