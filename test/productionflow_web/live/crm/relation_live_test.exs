defmodule ProductionflowWeb.CRM.RelationLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CRMFixtures

  alias Productionflow.CRM

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/relations")
    end
  end

  describe "without crm.view permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["orders.view"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/relations")
    end
  end

  describe "Index" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "lists relations and filters by search/type/archived", %{conn: conn} do
      printers = relation_fixture(%{name: "Printers Inc", code: "PRN", is_customer: true})
      supplier = relation_fixture(%{name: "Paper Supply", is_customer: false, is_supplier: true})
      archived = relation_fixture(%{name: "Old Co"})
      {:ok, _} = CRM.archive_relation(archived)

      {:ok, lv, _html} = live(conn, ~p"/relations")
      assert has_element?(lv, "#relations", "Printers Inc")
      assert has_element?(lv, "#relations", "Paper Supply")
      refute has_element?(lv, "#relations", "Old Co")

      # search
      lv |> form("#relation-filters", %{"search" => "printers"}) |> render_change()
      assert has_element?(lv, "#relations", "Printers Inc")
      refute has_element?(lv, "#relations", "Paper Supply")

      # type filter
      lv |> form("#relation-filters", %{"search" => "", "type" => "supplier"}) |> render_change()
      assert has_element?(lv, "#relations", "Paper Supply")
      refute has_element?(lv, "#relations", "Printers Inc")

      # include archived
      lv
      |> form("#relation-filters", %{"search" => "", "type" => "", "include_archived" => "true"})
      |> render_change()

      assert has_element?(lv, "#relations", "Old Co")
      assert printers.id && supplier.id
    end

    @tag permissions: ["crm.view"]
    test "view-only users see no New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/relations")
      refute html =~ "New relation"
    end

    @tag permissions: ["crm.manage"]
    test "managers see the New button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/relations")
      assert html =~ "New relation"
    end
  end

  describe "Form" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "view-only users cannot reach the new form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/relations/new")
    end

    @tag permissions: ["crm.manage"]
    test "creates a relation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/relations/new")

      lv
      |> form("#relation-form", relation: %{name: "Newco", is_customer: true, email: "a@b.com"})
      |> render_submit()

      relation = Enum.find(CRM.list_relations(), &(&1.name == "Newco"))
      assert relation
      assert_redirect(lv, ~p"/relations/#{relation}")
    end

    @tag permissions: ["crm.manage"]
    test "requires at least one type", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/relations/new")

      html =
        lv
        |> form("#relation-form", relation: %{name: "Notype"})
        |> render_submit()

      assert html =~ "select at least one type"
    end

    @tag permissions: ["crm.manage"]
    test "edits a relation", %{conn: conn} do
      relation = relation_fixture(%{name: "Before"})
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}/edit")

      lv
      |> form("#relation-form", relation: %{name: "After", is_customer: true})
      |> render_submit()

      assert CRM.get_relation!(relation.id).name == "After"
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.manage"]
    test "renders details, children, and adds a note", %{conn: conn} do
      relation = relation_fixture(%{name: "Shown", is_customer: true})
      address = address_fixture(relation, %{city: "Metropolis"})
      relation = CRM.get_relation!(relation.id)
      _contact = CRM.create_contact(relation, %{name: "Carl", address_id: address.id})

      {:ok, lv, html} = live(conn, ~p"/relations/#{relation}")
      assert html =~ "Shown"
      assert has_element?(lv, "#addresses", "Metropolis")
      assert has_element?(lv, "#contacts", "Carl")

      lv |> form("#note-form", note: %{body: "Spoke with Carl"}) |> render_submit()
      assert has_element?(lv, "#notes", "Spoke with Carl")
    end

    @tag permissions: ["crm.manage"]
    test "deletes a contact", %{conn: conn} do
      relation = relation_fixture()
      {:ok, _contact} = CRM.create_contact(relation, %{name: "Temp"})

      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}")
      assert has_element?(lv, "#contacts", "Temp")

      lv |> element("#contacts a", "Delete") |> render_click()
      refute has_element?(lv, "#contacts", "Temp")
      assert CRM.get_relation!(relation.id).contacts == []
    end

    @tag permissions: ["crm.manage"]
    test "archives and unarchives", %{conn: conn} do
      relation = relation_fixture()
      {:ok, lv, _html} = live(conn, ~p"/relations/#{relation}")

      lv |> element("button", "Archive") |> render_click()
      assert CRM.get_relation!(relation.id).archived_at

      lv |> element("button", "Unarchive") |> render_click()
      refute CRM.get_relation!(relation.id).archived_at
    end

    @tag permissions: ["crm.view"]
    test "view-only users see no mutating controls and the server rejects mutations", %{
      conn: conn
    } do
      relation = relation_fixture()
      {:ok, contact} = CRM.create_contact(relation, %{name: "Safe"})

      {:ok, lv, html} = live(conn, ~p"/relations/#{relation}")
      refute html =~ "Add contact"
      refute has_element?(lv, "#note-form")

      # Even pushing the event directly is rejected server-side.
      render_hook(lv, "delete_contact", %{"id" => contact.id})
      assert CRM.get_contact!(contact.id).id == contact.id
    end
  end
end
