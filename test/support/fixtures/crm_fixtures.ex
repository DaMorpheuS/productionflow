defmodule Productionflow.CRMFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Productionflow.CRM` context.
  """

  alias Productionflow.CRM

  def relation_fixture(attrs \\ %{}) do
    {:ok, relation} =
      attrs
      |> Enum.into(%{
        name: "Relation #{System.unique_integer([:positive])}",
        is_customer: true
      })
      |> CRM.create_relation()

    relation
  end

  def address_fixture(relation, attrs \\ %{}) do
    {:ok, address} =
      CRM.create_address(
        relation,
        Enum.into(attrs, %{kind: :delivery, street: "Main St 1", city: "Town"})
      )

    address
  end

  def contact_fixture(relation, attrs \\ %{}) do
    {:ok, contact} =
      CRM.create_contact(
        relation,
        Enum.into(attrs, %{name: "Contact #{System.unique_integer([:positive])}"})
      )

    contact
  end

  def note_fixture(relation, user, attrs \\ %{}) do
    {:ok, note} = CRM.create_note(relation, user, Enum.into(attrs, %{body: "A note"}))
    note
  end
end
