defmodule Productionflow.Accounts.Permissions do
  @moduledoc """
  The canonical list of permissions in the system.

  Permissions are dotted strings such as `"crm.manage"`. A
  `Productionflow.Accounts.Role` stores a subset of these, and
  `Productionflow.Accounts.Scope` exposes `can?/2` to check them.

  This module is the single source of truth: the role editor renders the
  grouped list, and `Role` changesets validate that stored permissions are a
  subset of it. Adding a permission here makes it available everywhere; adding
  a whole feature area is just a new group.
  """

  @groups [
    {"Administration",
     [
       {"admin.users", "Manage users"},
       {"admin.roles", "Manage roles"}
     ]},
    {"Relations",
     [
       {"crm.view", "View relations"},
       {"crm.manage", "Manage relations"}
     ]},
    {"Production",
     [
       {"production.view", "View production resources"},
       {"production.manage", "Manage production resources"}
     ]},
    {"Inventory",
     [
       {"inventory.view", "View materials & stock"},
       {"inventory.manage", "Manage materials"},
       {"inventory.book", "Book stock movements"}
     ]},
    {"Catalog",
     [
       {"catalog.view", "View product templates"},
       {"catalog.manage", "Manage product templates"}
     ]},
    {"Pricing",
     [
       {"pricing.view", "View price lists"},
       {"pricing.manage", "Manage price lists"}
     ]},
    {"Orders",
     [
       {"orders.view", "View orders"},
       {"orders.manage", "Manage orders"}
     ]},
    {"Planning",
     [
       {"planning.view", "View the planning board"},
       {"planning.manage", "Manage the planning board"}
     ]}
  ]

  @all for {_group, perms} <- @groups, {key, _label} <- perms, do: key

  @doc "Returns every permission key."
  def all, do: @all

  @doc """
  Returns permissions grouped for display as `[{group_label, [{key, label}]}]`.
  """
  def groups, do: @groups

  @doc "Returns true when `permission` is a known permission key."
  def valid?(permission), do: permission in @all

  @doc """
  Expands a list of permissions with the ones they imply.

  A `"<area>.manage"` permission implies `"<area>.view"` — being able to manage
  something always lets you see it. As a special case, `"inventory.book"` also
  implies `"inventory.view"` so a booking-only user can reach the material page
  (which lives in the view-gated live_session). Used by
  `Productionflow.Accounts.Scope` so a role only needs the higher permission.
  """
  def expand(permissions) do
    permissions
    |> Enum.flat_map(fn perm -> [perm | implied_by(perm)] end)
    |> Enum.uniq()
  end

  defp implied_by(permission) do
    case String.split(permission, ".") do
      [area, "manage"] -> Enum.filter(["#{area}.view"], &valid?/1)
      ["inventory", "book"] -> ["inventory.view"]
      _ -> []
    end
  end
end
