defmodule Productionflow.Accounts.PermissionsTest do
  use ExUnit.Case, async: true

  alias Productionflow.Accounts.Permissions

  describe "all/0" do
    test "returns a flat, unique list of permission keys" do
      all = Permissions.all()

      assert "admin.roles" in all
      assert "orders.manage" in all
      assert all == Enum.uniq(all)
    end

    test "every key is a dotted string" do
      assert Enum.all?(Permissions.all(), &(&1 =~ ~r/^[a-z]+\.[a-z_]+$/))
    end
  end

  describe "groups/0" do
    test "covers exactly the keys returned by all/0" do
      grouped = for {_group, perms} <- Permissions.groups(), {key, _label} <- perms, do: key
      assert Enum.sort(grouped) == Enum.sort(Permissions.all())
    end
  end

  describe "valid?/1" do
    test "is true for known permissions" do
      assert Permissions.valid?("admin.users")
    end

    test "is false for unknown permissions" do
      refute Permissions.valid?("admin.everything")
      refute Permissions.valid?("")
    end
  end
end
