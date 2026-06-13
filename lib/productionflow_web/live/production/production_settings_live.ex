defmodule ProductionflowWeb.Production.ProductionSettingsLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.Production

  @impl true
  def mount(_params, _session, socket) do
    settings = Production.get_settings()

    {:ok,
     socket
     |> assign(:page_title, gettext("Production settings"))
     |> assign(:settings, settings)
     |> assign_form(Production.change_settings(settings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Production settings")}
        <:subtitle>{gettext("Organization-wide values used in cost calculations.")}</:subtitle>
      </.header>

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:energy_price_per_kwh]}
          type="number"
          step="0.0001"
          label={gettext("Energy price per kWh (€)")}
          required
        />
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
    changeset = Production.change_settings(socket.assigns.settings, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Production.update_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign_form(Production.change_settings(settings))
         |> put_flash(:info, gettext("Settings saved."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "settings"))
  end
end
