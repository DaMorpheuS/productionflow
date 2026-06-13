defmodule Productionflow.CRM do
  @moduledoc """
  The CRM context: business relations and their contacts, addresses, and notes.

  CRM data is shared across the whole organization, so queries here are NOT
  filtered by the current user/scope. The acting user matters only when stamping
  authorship on a note.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo

  alias Productionflow.CRM.{Relation, Address, Contact, Note}

  ## Relations

  @doc """
  Lists relations ordered by name.

  ## Options
    * `:search` - case-insensitive match on name or code
    * `:type` - one of `:customer`, `:supplier`, `:prospect` to filter by flag
    * `:include_archived` - when true, also returns archived relations
  """
  def list_relations(opts \\ []) do
    Relation
    |> filter_archived(Keyword.get(opts, :include_archived, false))
    |> filter_search(Keyword.get(opts, :search))
    |> filter_type(Keyword.get(opts, :type))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp filter_archived(query, true), do: query
  defp filter_archived(query, _), do: where(query, [r], is_nil(r.archived_at))

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    like = "%#{String.replace(search, ~r/[%_]/, "")}%"
    where(query, [r], ilike(r.name, ^like) or ilike(r.code, ^like))
  end

  defp filter_type(query, :customer), do: where(query, [r], r.is_customer)
  defp filter_type(query, :supplier), do: where(query, [r], r.is_supplier)
  defp filter_type(query, :prospect), do: where(query, [r], r.is_prospect)
  defp filter_type(query, _), do: query

  @doc "Gets a relation with addresses, contacts (with their address), and notes (newest first)."
  def get_relation!(id) do
    notes_query = from(n in Note, order_by: [desc: n.inserted_at, desc: n.id], preload: :user)

    Relation
    |> Repo.get!(id)
    |> Repo.preload([:addresses, [contacts: :address], [notes: notes_query]])
  end

  @doc "Returns a changeset for a relation."
  def change_relation(%Relation{} = relation, attrs \\ %{}) do
    Relation.changeset(relation, attrs)
  end

  @doc "Creates a relation."
  def create_relation(attrs) do
    %Relation{}
    |> Relation.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a relation."
  def update_relation(%Relation{} = relation, attrs) do
    relation
    |> Relation.changeset(attrs)
    |> Repo.update()
  end

  @doc "Archives a relation (soft hide from default lists)."
  def archive_relation(%Relation{} = relation) do
    relation
    |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  @doc "Restores an archived relation."
  def unarchive_relation(%Relation{} = relation) do
    relation
    |> Ecto.Changeset.change(archived_at: nil)
    |> Repo.update()
  end

  @doc "Hard-deletes a relation and its children (cascades)."
  def delete_relation(%Relation{} = relation), do: Repo.delete(relation)

  ## Addresses

  @doc "Gets an address."
  def get_address!(id), do: Repo.get!(Address, id)

  @doc "Returns a changeset for an address."
  def change_address(%Address{} = address, attrs \\ %{}) do
    Address.changeset(address, attrs)
  end

  @doc "Creates an address under the given relation, enforcing a single default."
  def create_address(%Relation{} = relation, attrs) do
    changeset = Address.changeset(%Address{relation_id: relation.id}, attrs)

    Repo.transact(fn ->
      with {:ok, address} <- Repo.insert(changeset) do
        clear_other_defaults(address)
        {:ok, address}
      end
    end)
  end

  @doc "Updates an address, enforcing a single default per relation."
  def update_address(%Address{} = address, attrs) do
    changeset = Address.changeset(address, attrs)

    Repo.transact(fn ->
      with {:ok, address} <- Repo.update(changeset) do
        clear_other_defaults(address)
        {:ok, address}
      end
    end)
  end

  @doc "Deletes an address (contacts keep existing, their location is cleared)."
  def delete_address(%Address{} = address), do: Repo.delete(address)

  # When an address is marked default, unset the flag on the relation's others.
  defp clear_other_defaults(%Address{is_default: true} = address) do
    from(a in Address,
      where: a.relation_id == ^address.relation_id and a.id != ^address.id and a.is_default
    )
    |> Repo.update_all(set: [is_default: false])
  end

  defp clear_other_defaults(_address), do: :ok

  ## Contacts

  @doc "Gets a contact."
  def get_contact!(id), do: Repo.get!(Contact, id)

  @doc "Returns a changeset for a contact, validating address choices against the relation."
  def change_contact(%Relation{} = relation, %Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs, address_ids: address_ids(relation))
  end

  @doc """
  Creates a contact under the relation.

  When `location_attrs` is given (a new location was entered in the form), the
  address is created under the relation first and the contact is linked to it,
  all in one transaction.
  """
  def create_contact(relation, contact_attrs, location_attrs \\ nil)

  def create_contact(%Relation{} = relation, contact_attrs, nil) do
    %Contact{relation_id: relation.id}
    |> Contact.changeset(contact_attrs, address_ids: address_ids(relation))
    |> Repo.insert()
  end

  def create_contact(%Relation{} = relation, contact_attrs, location_attrs) do
    Repo.transact(fn ->
      with {:ok, address} <- create_address(relation, location_attrs) do
        %Contact{relation_id: relation.id, address_id: address.id}
        |> Contact.changeset(contact_attrs, address_ids: [address.id])
        |> Repo.insert()
      end
    end)
  end

  @doc "Updates a contact. Pass `location_attrs` to create + link a new location."
  def update_contact(relation, contact, contact_attrs, location_attrs \\ nil)

  def update_contact(%Relation{} = relation, %Contact{} = contact, contact_attrs, nil) do
    contact
    |> Contact.changeset(contact_attrs, address_ids: address_ids(relation))
    |> Repo.update()
  end

  def update_contact(%Relation{} = relation, %Contact{} = contact, contact_attrs, location_attrs) do
    Repo.transact(fn ->
      with {:ok, address} <- create_address(relation, location_attrs) do
        contact
        |> Contact.changeset(
          Map.put(contact_attrs, "address_id", address.id),
          address_ids: [address.id]
        )
        |> Repo.update()
      end
    end)
  end

  @doc "Deletes a contact."
  def delete_contact(%Contact{} = contact), do: Repo.delete(contact)

  defp address_ids(%Relation{addresses: addresses}) when is_list(addresses),
    do: Enum.map(addresses, & &1.id)

  defp address_ids(%Relation{} = relation) do
    from(a in Address, where: a.relation_id == ^relation.id, select: a.id) |> Repo.all()
  end

  ## Notes

  @doc "Returns a changeset for a note."
  def change_note(%Note{} = note, attrs \\ %{}) do
    Note.changeset(note, attrs)
  end

  @doc "Creates a note authored by the given user under the relation."
  def create_note(%Relation{} = relation, user, attrs) do
    %Note{relation_id: relation.id, user_id: user && user.id}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a note."
  def delete_note(%Note{} = note), do: Repo.delete(note)
end
