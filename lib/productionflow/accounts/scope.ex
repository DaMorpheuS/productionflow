defmodule Productionflow.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Productionflow.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Productionflow.Accounts.{User, Role}

  defstruct user: nil, permissions: MapSet.new()

  @doc """
  Creates a scope for the given user.

  The user's role permissions are loaded into a `MapSet` for fast `can?/2`
  checks. The role association must be preloaded; if it is not loaded the scope
  carries no permissions (a safe deny-by-default).

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user, permissions: permissions_for(user)}
  end

  def for_user(nil), do: nil

  defp permissions_for(%User{role: %Role{permissions: permissions}}), do: MapSet.new(permissions)
  defp permissions_for(_user), do: MapSet.new()

  @doc """
  Returns true when the scope's user has the given permission.

  A nil scope (no logged-in user) never has any permission.
  """
  def can?(%__MODULE__{permissions: permissions}, permission) when is_binary(permission) do
    MapSet.member?(permissions, permission)
  end

  def can?(nil, _permission), do: false

  @doc """
  Returns true when the scope can reach the administration section, i.e. it has
  any `admin.*` permission.
  """
  def admin?(%__MODULE__{} = scope), do: can?(scope, "admin.users") or can?(scope, "admin.roles")
  def admin?(nil), do: false
end
