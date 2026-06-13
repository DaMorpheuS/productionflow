defmodule ProductionflowWeb.Admin.UserLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.Accounts
  alias Productionflow.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@subtitle}</:subtitle>
      </.header>

      <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
        <.input
          :if={@live_action == :new}
          field={@form[:email]}
          type="email"
          label={gettext("Email")}
          autocomplete="off"
          required
        />
        <p :if={@live_action == :edit} class="text-sm text-base-content/70">
          {gettext("Email")}: <span class="font-semibold">{@user.email}</span>
        </p>

        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input
          field={@form[:role_id]}
          type="select"
          label={gettext("Role")}
          prompt={gettext("Select a role")}
          options={@role_options}
          required
        />
        <.input field={@form[:active]} type="checkbox" label={gettext("Active")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {(@live_action == :new && gettext("Create user")) || gettext("Save user")}
          </.button>
          <.button navigate={~p"/admin/users"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, :role_options, role_options())
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    user = %User{active: true}

    socket
    |> assign(:page_title, gettext("New user"))
    |> assign(:subtitle, gettext("They will receive an email to confirm their account."))
    |> assign(:user, user)
    |> assign_form(Accounts.change_user_creation(user, %{}, validate_unique: false))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user_with_role!(id)

    socket
    |> assign(:page_title, gettext("Edit user"))
    |> assign(:subtitle, gettext("Update the user's profile and role."))
    |> assign(:user, user)
    |> assign_form(Accounts.change_user_admin(user))
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = change_for_action(socket, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.live_action, user_params)
  end

  defp save_user(socket, :new, user_params) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("User created. A login email was sent to %{email}.", email: user.email)
         )
         |> push_navigate(to: ~p"/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user(socket, :edit, user_params) do
    case Accounts.update_user(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("User updated."))
         |> push_navigate(to: ~p"/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp change_for_action(%{assigns: %{live_action: :new}} = socket, params, opts) do
    Accounts.change_user_creation(socket.assigns.user, params, opts)
  end

  defp change_for_action(%{assigns: %{live_action: :edit}} = socket, params, _opts) do
    Accounts.change_user_admin(socket.assigns.user, params)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  defp role_options do
    Enum.map(Accounts.list_roles(), &{&1.name, &1.id})
  end
end
