defmodule ProductionflowWeb.Admin.UserLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> stream(:users, Accounts.list_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Users")}
        <:subtitle>{gettext("Invite staff and assign their role.")}</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/users/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New user")}
          </.button>
        </:actions>
      </.header>

      <.table id="users" rows={@streams.users}>
        <:col :let={{_id, user}} label={gettext("Email")}>
          <span class="font-semibold">{user.email}</span>
        </:col>
        <:col :let={{_id, user}} label={gettext("Name")}>{user.name}</:col>
        <:col :let={{_id, user}} label={gettext("Role")}>
          {user.role && user.role.name}
        </:col>
        <:col :let={{_id, user}} label={gettext("Status")}>
          <span class={["badge", (user.active && "badge-success") || "badge-ghost"]}>
            {(user.active && gettext("Active")) || gettext("Inactive")}
          </span>
        </:col>
        <:action :let={{_id, user}}>
          <.link navigate={~p"/admin/users/#{user}/edit"}>{gettext("Edit")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
