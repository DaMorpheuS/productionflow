defmodule ProductionflowWeb.Orders.OrderSettingsLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.Orders

  @impl true
  def mount(_params, _session, socket) do
    settings = Orders.get_settings()

    {:ok,
     socket
     |> assign(:page_title, gettext("Order numbering"))
     |> assign(:settings, settings)
     |> assign(:mode_options, mode_options())
     |> assign_form(Orders.change_settings(settings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Order numbering")}
        <:subtitle>{gettext("How new order numbers are generated.")}</:subtitle>
      </.header>

      <.form for={@form} id="order-settings-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:number_mode]}
            type="select"
            label={gettext("Numbering")}
            options={@mode_options}
          />
          <.input field={@form[:number_prefix]} type="text" label={gettext("Prefix")} required />
        </div>
        <p class="mt-2 text-sm text-base-content/60">
          {gettext(
            "Per-year resets the counter each year (e.g. ORD-2026-0001); continuous never resets (e.g. ORD-0001)."
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
    changeset = Orders.change_settings(socket.assigns.settings, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Orders.update_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign_form(Orders.change_settings(settings))
         |> put_flash(:info, gettext("Settings saved."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "settings"))
  end

  defp mode_options do
    [{gettext("Per year"), "per_year"}, {gettext("Continuous"), "continuous"}]
  end
end
