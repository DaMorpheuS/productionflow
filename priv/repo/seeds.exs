# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Productionflow.Repo.insert!(%Productionflow.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias Productionflow.Repo
alias Productionflow.Accounts
alias Productionflow.Accounts.{Role, User, Permissions}

# Idempotent: an Administrator role holding every permission, and an admin user
# assigned to it. Re-running keeps both in sync.

admin_role =
  case Repo.get_by(Role, name: "Administrator") do
    nil ->
      {:ok, role} =
        Accounts.create_role(%{
          name: "Administrator",
          description: "Full access to every part of the system.",
          permissions: Permissions.all()
        })

      role

    role ->
      {:ok, role} = Accounts.update_role(role, %{permissions: Permissions.all()})
      role
  end

admin_email = System.get_env("ADMIN_EMAIL", "admin@productionflow.local")

case Repo.get_by(User, email: admin_email) do
  nil ->
    {:ok, _user} =
      Accounts.create_user(%{
        email: admin_email,
        name: "Administrator",
        active: true,
        role_id: admin_role.id
      })

    IO.puts("""
    Created admin user #{admin_email}.
    Log in via the magic link: visit /users/log-in, enter the email, then open
    /dev/mailbox to follow the login link and set a password.
    """)

  user ->
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role_id: admin_role.id])
    IO.puts("Admin user #{admin_email} already exists; ensured Administrator role.")
end
