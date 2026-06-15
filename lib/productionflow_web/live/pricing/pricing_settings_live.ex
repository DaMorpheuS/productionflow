defmodule ProductionflowWeb.Pricing.PricingSettingsLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.Pricing

  @impl true
  def mount(_params, _session, socket) do
    settings = Pricing.get_settings()

    {:ok,
     socket
     |> assign(:page_title, gettext("Pricing settings"))
     |> assign(:settings, settings)
     |> assign_form(Pricing.change_settings(settings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Pricing settings")}
        <:subtitle>
          {gettext("The default margin added to internal cost when no price list applies.")}
        </:subtitle>
      </.header>

      <.form for={@form} id="pricing-settings-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:default_margin_pct]}
          type="number"
          step="0.01"
          min="0"
          label={gettext("Default margin % (markup on cost)")}
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
    changeset = Pricing.change_settings(socket.assigns.settings, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Pricing.update_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign_form(Pricing.change_settings(settings))
         |> put_flash(:info, gettext("Settings saved."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "settings"))
  end
end
