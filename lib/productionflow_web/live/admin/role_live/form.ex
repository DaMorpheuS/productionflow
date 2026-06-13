defmodule ProductionflowWeb.Admin.RoleLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.Accounts
  alias Productionflow.Accounts.{Role, Permissions}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{gettext("Choose the permissions this role grants.")}</:subtitle>
      </.header>

      <.form for={@form} id="role-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} required />
        <.input field={@form[:description]} type="text" label={gettext("Description")} />

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Permissions")}</legend>
          <input type="hidden" name="role[permissions][]" value="" />

          <div class="mt-2 grid gap-6 sm:grid-cols-2">
            <div :for={{group, perms} <- Permissions.groups()} class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                {group}
              </p>
              <label :for={{key, label} <- perms} class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  name="role[permissions][]"
                  value={key}
                  checked={permission_checked?(@form, key)}
                />
                {label}
              </label>
            </div>
          </div>
        </fieldset>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save role")}
          </.button>
          <.button navigate={~p"/admin/roles"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    role = %Role{}

    socket
    |> assign(:page_title, gettext("New role"))
    |> assign(:role, role)
    |> assign_form(Accounts.change_role(role))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    role = Accounts.get_role!(id)

    socket
    |> assign(:page_title, gettext("Edit role"))
    |> assign(:role, role)
    |> assign_form(Accounts.change_role(role))
  end

  @impl true
  def handle_event("validate", %{"role" => role_params}, socket) do
    changeset = Accounts.change_role(socket.assigns.role, role_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"role" => role_params}, socket) do
    save_role(socket, socket.assigns.live_action, role_params)
  end

  defp save_role(socket, :new, role_params) do
    case Accounts.create_role(role_params) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role created."))
         |> push_navigate(to: ~p"/admin/roles")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_role(socket, :edit, role_params) do
    case Accounts.update_role(socket.assigns.role, role_params) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Role updated."))
         |> push_navigate(to: ~p"/admin/roles")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp permission_checked?(form, key) do
    case form[:permissions].value do
      list when is_list(list) -> key in list
      _ -> false
    end
  end
end
