defmodule ProductionflowWeb.Planning.SettingsLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.Planning

  @impl true
  def mount(_params, _session, socket) do
    settings = Planning.get_settings()

    {:ok,
     socket
     |> assign(:page_title, gettext("Planning settings"))
     |> assign(:settings, settings)
     |> assign_form(Planning.change_settings(settings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Planning settings")}
        <:subtitle>{gettext("Controls how the scheduling board lays out work over time.")}</:subtitle>
        <:actions>
          <.button navigate={~p"/planning"}>{gettext("Back to board")}</.button>
        </:actions>
      </.header>

      <.form for={@form} id="planning-settings-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:schedule_from]}
          type="date"
          label={gettext("Schedule from")}
        />
        <p class="mt-1 text-xs text-base-content/60">
          {gettext(
            "The date queues are packed forward from. Leave blank to start from today; a past date is treated as today."
          )}
        </p>
        <div class="mt-6">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save settings")}
          </.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset = Planning.change_settings(socket.assigns.settings, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Planning.update_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign_form(Planning.change_settings(settings))
         |> put_flash(:info, gettext("Settings saved."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "settings"))
  end
end
