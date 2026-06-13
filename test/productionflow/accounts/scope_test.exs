defmodule Productionflow.Accounts.ScopeTest do
  use Productionflow.DataCase, async: true

  import Productionflow.AccountsFixtures

  alias Productionflow.Accounts.Scope

  describe "for_user/1" do
    test "returns nil for nil" do
      assert Scope.for_user(nil) == nil
    end

    test "loads the role's permissions into a MapSet" do
      user = user_fixture_with_permissions(["crm.view", "crm.manage"])
      scope = Scope.for_user(user)

      assert scope.permissions == MapSet.new(["crm.view", "crm.manage"])
    end

    test "has no permissions when the role is not loaded" do
      scope = Scope.for_user(user_fixture())
      assert scope.permissions == MapSet.new()
    end
  end

  describe "can?/2" do
    test "is true only for granted permissions" do
      scope = Scope.for_user(user_fixture_with_permissions(["orders.view"]))

      assert Scope.can?(scope, "orders.view")
      refute Scope.can?(scope, "orders.manage")
    end

    test "a nil scope can do nothing" do
      refute Scope.can?(nil, "orders.view")
    end
  end

  describe "admin?/1" do
    test "is true with any admin permission" do
      assert Scope.admin?(Scope.for_user(user_fixture_with_permissions(["admin.users"])))
      assert Scope.admin?(Scope.for_user(user_fixture_with_permissions(["admin.roles"])))
    end

    test "is false without admin permissions" do
      refute Scope.admin?(Scope.for_user(user_fixture_with_permissions(["crm.view"])))
      refute Scope.admin?(nil)
    end
  end
end
