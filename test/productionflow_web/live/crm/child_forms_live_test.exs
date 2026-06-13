defmodule ProductionflowWeb.CRM.ChildFormsLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CRMFixtures

  alias Productionflow.CRM

  describe "AddressLive.Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.manage"]
    test "adds an address to a relation", %{conn: conn} do
      relation = relation_fixture()
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/addresses/new")

      lv
      |> form("#address-form",
        address: %{kind: "invoice", street: "Bill St 5", city: "Payton", is_default: true}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/relations/#{relation}")
      relation = CRM.get_relation!(relation.id)
      assert [address] = relation.addresses
      assert address.kind == :invoice
      assert address.is_default
    end

    @tag permissions: ["crm.manage"]
    test "requires street and city", %{conn: conn} do
      relation = relation_fixture()
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/addresses/new")

      html = lv |> form("#address-form", address: %{kind: "delivery"}) |> render_submit()
      assert html =~ "can&#39;t be blank"
    end
  end

  describe "ContactLive.Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.manage"]
    test "adds a contact linked to an existing location", %{conn: conn} do
      relation = relation_fixture()
      address = address_fixture(relation, %{city: "Existingville"})
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/contacts/new")

      lv
      |> form("#contact-form", contact: %{name: "Linked", address_id: address.id})
      |> render_submit()

      assert_redirect(lv, ~p"/relations/#{relation}")
      relation = CRM.get_relation!(relation.id)
      assert [contact] = relation.contacts
      assert contact.address_id == address.id
    end

    @tag permissions: ["crm.manage"]
    test "creates a new location inline and links the contact", %{conn: conn} do
      relation = relation_fixture()
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/contacts/new")

      # Toggle to the new-location form.
      lv |> element("button", "New location") |> render_click()

      lv
      |> form("#contact-form",
        contact: %{name: "On Site"},
        location: %{kind: "delivery", street: "Plant 1", city: "Industria"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/relations/#{relation}")
      relation = CRM.get_relation!(relation.id)
      assert [contact] = relation.contacts
      assert [address] = relation.addresses
      assert contact.address_id == address.id
      assert address.city == "Industria"
    end

    @tag permissions: ["crm.manage"]
    test "requires a name", %{conn: conn} do
      relation = relation_fixture()
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/contacts/new")

      html = lv |> form("#contact-form", contact: %{name: ""}) |> render_submit()
      assert html =~ "can&#39;t be blank"
    end
  end
end
