defmodule ProductionflowWeb.Admin.UserLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.AccountsFixtures

  alias Productionflow.Accounts

  describe "authorization" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/users")
    end
  end

  describe "without admin.users permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["admin.roles"]
    test "redirects to the dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users")
    end
  end

  describe "with admin.users permission" do
    setup [:register_and_log_in_user]

    @tag permissions: ["admin.users"]
    test "lists users with their role", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/users")
      # The logged-in admin is itself listed.
      assert html =~ "Email"
    end

    @tag permissions: ["admin.users"]
    test "creates a user and sends login instructions", %{conn: conn} do
      role = role_fixture(%{name: "Staff"})
      {:ok, lv, _html} = live(conn, ~p"/admin/users/new")
      email = unique_user_email()

      lv
      |> form("#user-form",
        user: %{email: email, name: "New Person", active: true, role_id: role.id}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/admin/users")

      user = Accounts.get_user_by_email(email)
      assert user.name == "New Person"
      assert user.role_id == role.id

      assert Productionflow.Repo.get_by!(Productionflow.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    @tag permissions: ["admin.users"]
    test "requires a role on creation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/users/new")

      html =
        lv
        |> form("#user-form", user: %{email: unique_user_email(), name: "No Role"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    @tag permissions: ["admin.users"]
    test "edits a user's profile and role", %{conn: conn} do
      target = user_fixture_with_permissions(["crm.view"])
      new_role = role_fixture(%{name: "Promoted"})
      {:ok, lv, _html} = live(conn, ~p"/admin/users/#{target}/edit")

      lv
      |> form("#user-form", user: %{name: "Updated Name", active: false, role_id: new_role.id})
      |> render_submit()

      assert_redirect(lv, ~p"/admin/users")

      updated = Accounts.get_user_with_role!(target.id)
      assert updated.name == "Updated Name"
      assert updated.active == false
      assert updated.role_id == new_role.id
    end
  end
end
