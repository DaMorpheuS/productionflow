defmodule Productionflow.CRMTest do
  use Productionflow.DataCase, async: true

  import Productionflow.CRMFixtures
  import Productionflow.AccountsFixtures

  alias Productionflow.CRM
  alias Productionflow.CRM.{Relation, Contact, Note}

  describe "create_relation/1" do
    test "creates a relation with a type" do
      assert {:ok, %Relation{} = relation} =
               CRM.create_relation(%{name: "Acme", is_customer: true})

      assert relation.name == "Acme"
      assert relation.is_customer
    end

    test "requires a name" do
      assert {:error, changeset} = CRM.create_relation(%{is_customer: true})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires at least one type" do
      assert {:error, changeset} = CRM.create_relation(%{name: "Notype"})
      assert %{is_customer: ["select at least one type"]} = errors_on(changeset)
    end

    test "normalizes a blank code to nil and allows many" do
      assert {:ok, a} = CRM.create_relation(%{name: "A", is_customer: true, code: "  "})
      assert {:ok, b} = CRM.create_relation(%{name: "B", is_customer: true, code: ""})
      assert is_nil(a.code)
      assert is_nil(b.code)
    end

    test "rejects a duplicate code" do
      relation_fixture(%{code: "C-1"})

      assert {:error, changeset} =
               CRM.create_relation(%{name: "Dup", is_customer: true, code: "C-1"})

      assert %{code: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_relations/1" do
    test "excludes archived by default, includes them on request" do
      active = relation_fixture(%{name: "Active"})
      archived = relation_fixture(%{name: "Archived"})
      {:ok, _} = CRM.archive_relation(archived)

      assert Enum.map(CRM.list_relations(), & &1.id) == [active.id]

      ids = CRM.list_relations(include_archived: true) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([active.id, archived.id])
    end

    test "filters by search on name or code" do
      a = relation_fixture(%{name: "Printers Inc", code: "PRN"})
      _b = relation_fixture(%{name: "Other Co", code: "OTH"})

      assert [found] = CRM.list_relations(search: "print")
      assert found.id == a.id

      assert [by_code] = CRM.list_relations(search: "prn")
      assert by_code.id == a.id
    end

    test "filters by type" do
      cust = relation_fixture(%{name: "Cust", is_customer: true, is_supplier: false})
      supp = relation_fixture(%{name: "Supp", is_customer: false, is_supplier: true})

      assert [c] = CRM.list_relations(type: :customer)
      assert c.id == cust.id
      assert [s] = CRM.list_relations(type: :supplier)
      assert s.id == supp.id
    end
  end

  describe "addresses" do
    setup do
      %{relation: relation_fixture()}
    end

    test "create requires kind, street, city", %{relation: relation} do
      assert {:error, changeset} = CRM.create_address(relation, %{street: nil, city: nil})
      errors = errors_on(changeset)
      assert errors[:street]
      assert errors[:city]
    end

    test "enforces a single default per relation", %{relation: relation} do
      first = address_fixture(relation, %{is_default: true})
      second = address_fixture(relation, %{is_default: true})

      assert CRM.get_address!(first.id).is_default == false
      assert CRM.get_address!(second.id).is_default == true
    end
  end

  describe "contacts" do
    setup do
      %{relation: relation_fixture()}
    end

    test "creates a contact under the relation", %{relation: relation} do
      assert {:ok, %Contact{} = contact} = CRM.create_contact(relation, %{name: "Jane"})
      assert contact.relation_id == relation.id
      assert is_nil(contact.address_id)
    end

    test "requires a name", %{relation: relation} do
      assert {:error, changeset} = CRM.create_contact(relation, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "links to an existing address of the relation", %{relation: relation} do
      address = address_fixture(relation)
      relation = CRM.get_relation!(relation.id)

      assert {:ok, contact} =
               CRM.create_contact(relation, %{name: "Bob", address_id: address.id})

      assert contact.address_id == address.id
    end

    test "rejects an address belonging to another relation", %{relation: relation} do
      other = relation_fixture()
      foreign = address_fixture(other)
      relation = CRM.get_relation!(relation.id)

      assert {:error, changeset} =
               CRM.create_contact(relation, %{name: "X", address_id: foreign.id})

      assert %{address_id: ["is invalid"]} = errors_on(changeset)
    end

    test "creates a new location and links the contact in one step", %{relation: relation} do
      assert {:ok, contact} =
               CRM.create_contact(relation, %{name: "Site Lead"}, %{
                 kind: :delivery,
                 street: "Plant Rd 9",
                 city: "Industria"
               })

      assert contact.address_id
      relation = CRM.get_relation!(relation.id)
      assert Enum.any?(relation.addresses, &(&1.id == contact.address_id))
    end

    test "rolls back the new location if the contact is invalid", %{relation: relation} do
      assert {:error, _changeset} =
               CRM.create_contact(relation, %{name: ""}, %{
                 kind: :delivery,
                 street: "Nowhere",
                 city: "Void"
               })

      relation = CRM.get_relation!(relation.id)
      assert relation.addresses == []
    end

    test "deleting an address nilifies its contacts' location", %{relation: relation} do
      address = address_fixture(relation)
      relation = CRM.get_relation!(relation.id)
      {:ok, contact} = CRM.create_contact(relation, %{name: "Linked", address_id: address.id})

      assert {:ok, _} = CRM.delete_address(address)
      assert CRM.get_contact!(contact.id).address_id == nil
    end
  end

  describe "notes" do
    setup do
      user = user_fixture()
      %{relation: relation_fixture(), user: user}
    end

    test "creates a note with author and body", %{relation: relation, user: user} do
      assert {:ok, %Note{} = note} = CRM.create_note(relation, user, %{body: "Called them"})
      assert note.user_id == user.id
      assert note.body == "Called them"
    end

    test "requires a body", %{relation: relation, user: user} do
      assert {:error, changeset} = CRM.create_note(relation, user, %{body: ""})
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_relation! returns notes newest-first with the author", %{
      relation: relation,
      user: user
    } do
      {:ok, _old} = CRM.create_note(relation, user, %{body: "first"})
      {:ok, _new} = CRM.create_note(relation, user, %{body: "second"})

      relation = CRM.get_relation!(relation.id)
      assert Enum.map(relation.notes, & &1.body) == ["second", "first"]
      assert hd(relation.notes).user.id == user.id
    end
  end
end
