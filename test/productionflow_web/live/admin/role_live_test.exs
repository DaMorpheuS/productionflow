defmodule ProductionflowWeb.Admin.RoleLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.AccountsFixtures

  alias Productionflow.Accounts

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/roles")
    end
  end

  describe "without admin.roles permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["crm.view"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/roles")
    end
  end

  describe "with admin.roles permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["admin.roles"]
    test "lists existing roles", %{conn: conn} do
      role_fixture(%{name: "Warehouse"})
      {:ok, _lv, html} = live(conn, ~p"/admin/roles")
      assert html =~ "Warehouse"
    end

    @tag permissions: ["admin.roles"]
    test "creates a role with selected permissions", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/roles/new")

      lv
      |> form("#role-form",
        role: %{name: "Office", description: "Office staff", permissions: ["crm.view"]}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/admin/roles")

      role = Enum.find(Accounts.list_roles(), &(&1.name == "Office"))
      assert role.permissions == ["crm.view"]
    end

    @tag permissions: ["admin.roles"]
    test "requires a name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/roles/new")

      html =
        lv
        |> form("#role-form", role: %{name: "", permissions: []})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    @tag permissions: ["admin.roles"]
    test "edits an existing role", %{conn: conn} do
      role = role_fixture(%{name: "Editable", permissions: ["crm.view"]})
      {:ok, lv, _html} = live(conn, ~p"/admin/roles/#{role}/edit")

      lv
      |> form("#role-form", role: %{name: "Edited", permissions: ["orders.manage"]})
      |> render_submit()

      assert_redirect(lv, ~p"/admin/roles")

      updated = Accounts.get_role!(role.id)
      assert updated.name == "Edited"
      assert updated.permissions == ["orders.manage"]
    end

    @tag permissions: ["admin.roles"]
    test "deletes an unassigned role", %{conn: conn} do
      role = role_fixture(%{name: "Removable"})
      {:ok, lv, _html} = live(conn, ~p"/admin/roles")

      lv |> element("#roles-#{role.id} a", "Delete") |> render_click()

      refute Enum.any?(Accounts.list_roles(), &(&1.id == role.id))
    end
  end
end
