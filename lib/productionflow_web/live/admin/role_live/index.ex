defmodule ProductionflowWeb.Admin.RoleLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Roles"))
     |> stream(:roles, Accounts.list_roles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Roles")}
        <:subtitle>{gettext("Define what each group of users is allowed to do.")}</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/roles/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New role")}
          </.button>
        </:actions>
      </.header>

      <.table id="roles" rows={@streams.roles}>
        <:col :let={{_id, role}} label={gettext("Name")}>
          <span class="font-semibold">{role.name}</span>
        </:col>
        <:col :let={{_id, role}} label={gettext("Description")}>{role.description}</:col>
        <:col :let={{_id, role}} label={gettext("Permissions")}>
          {ngettext("%{count} permission", "%{count} permissions", length(role.permissions))}
        </:col>
        <:action :let={{_id, role}}>
          <.link navigate={~p"/admin/roles/#{role}/edit"}>{gettext("Edit")}</.link>
        </:action>
        <:action :let={{id, role}}>
          <.link
            phx-click={JS.push("delete", value: %{id: role.id}) |> hide("##{id}")}
            data-confirm={gettext("Delete this role?")}
          >
            {gettext("Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    role = Accounts.get_role!(id)

    case Accounts.delete_role(role) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role deleted."))
         |> stream_delete(:roles, role)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("This role is still assigned to one or more users."))
         |> stream_insert(:roles, role)}
    end
  end
end
