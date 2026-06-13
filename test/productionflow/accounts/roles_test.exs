defmodule Productionflow.Accounts.RolesTest do
  use Productionflow.DataCase, async: true

  import Productionflow.AccountsFixtures

  alias Productionflow.Accounts
  alias Productionflow.Accounts.Role

  describe "create_role/1" do
    test "creates a role with valid permissions" do
      assert {:ok, %Role{} = role} =
               Accounts.create_role(%{name: "Sales", permissions: ["crm.view", "crm.manage"]})

      assert role.name == "Sales"
      assert role.permissions == ["crm.view", "crm.manage"]
    end

    test "requires a name" do
      assert {:error, changeset} = Accounts.create_role(%{permissions: []})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects unknown permissions" do
      assert {:error, changeset} =
               Accounts.create_role(%{name: "Bad", permissions: ["crm.view", "made.up"]})

      assert %{permissions: ["contains unknown permissions: made.up"]} = errors_on(changeset)
    end

    test "strips blanks and de-duplicates permissions" do
      assert {:ok, role} =
               Accounts.create_role(%{name: "Dedup", permissions: ["", "crm.view", "crm.view"]})

      assert role.permissions == ["crm.view"]
    end

    test "enforces unique names" do
      role_fixture(%{name: "Dupe"})
      assert {:error, changeset} = Accounts.create_role(%{name: "Dupe"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_role/2" do
    test "updates permissions" do
      role = role_fixture(%{permissions: ["crm.view"]})
      assert {:ok, role} = Accounts.update_role(role, %{permissions: ["orders.manage"]})
      assert role.permissions == ["orders.manage"]
    end
  end

  describe "delete_role/1" do
    test "deletes an unassigned role" do
      role = role_fixture()
      assert {:ok, _} = Accounts.delete_role(role)
      assert Accounts.list_roles() == []
    end

    test "refuses to delete a role still assigned to a user" do
      user = user_fixture_with_permissions(["crm.view"])
      role = Accounts.get_role!(user.role_id)

      assert {:error, changeset} = Accounts.delete_role(role)
      assert %{users: ["is still assigned to one or more users"]} = errors_on(changeset)
      assert Accounts.get_role!(role.id)
    end
  end

  describe "admin user management" do
    test "create_user/1 sets profile and role, leaving the user unconfirmed" do
      role = role_fixture()

      assert {:ok, user} =
               Accounts.create_user(%{
                 email: unique_user_email(),
                 name: "Jane",
                 active: true,
                 role_id: role.id
               })

      assert user.name == "Jane"
      assert user.role_id == role.id
      assert is_nil(user.confirmed_at)
      assert is_nil(user.hashed_password)
    end

    test "create_user/1 requires a role" do
      assert {:error, changeset} = Accounts.create_user(%{email: unique_user_email()})
      assert %{role_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_user/2 changes role and active but never email" do
      user = user_fixture_with_permissions(["crm.view"])
      other_role = role_fixture(%{permissions: ["orders.view"]})
      original_email = user.email

      assert {:ok, updated} =
               Accounts.update_user(user, %{
                 name: "Renamed",
                 active: false,
                 role_id: other_role.id,
                 email: "hacker@example.com"
               })

      assert updated.name == "Renamed"
      assert updated.active == false
      assert updated.role_id == other_role.id
      assert updated.email == original_email
    end

    test "list_users/0 preloads roles" do
      user = user_fixture_with_permissions(["crm.view"])
      assert [loaded] = Accounts.list_users()
      assert loaded.id == user.id
      assert loaded.role.id == user.role_id
    end
  end
end
