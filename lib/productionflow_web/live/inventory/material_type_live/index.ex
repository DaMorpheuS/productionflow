defmodule ProductionflowWeb.Inventory.MaterialTypeLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Material types"))
     |> stream(:types, Inventory.list_material_types())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Material types")}
        <:subtitle>{gettext("Define custom fields per kind of material.")}</:subtitle>
        <:actions>
          <.button navigate={~p"/inventory/materials"}>{gettext("Back to materials")}</.button>
          <.button variant="primary" navigate={~p"/inventory/types/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New type")}
          </.button>
        </:actions>
      </.header>

      <.table id="types" rows={@streams.types}>
        <:col :let={{_id, type}} label={gettext("Name")}>
          <.link navigate={~p"/inventory/types/#{type}"} class="font-semibold hover:underline">
            {type.name}
          </.link>
        </:col>
        <:action :let={{_id, type}}>
          <.link navigate={~p"/inventory/types/#{type}"}>{gettext("Fields")}</.link>
        </:action>
        <:action :let={{_id, type}}>
          <.link navigate={~p"/inventory/types/#{type}/edit"}>{gettext("Edit")}</.link>
        </:action>
        <:action :let={{id, type}}>
          <.link
            phx-click={JS.push("delete", value: %{id: type.id}) |> hide("##{id}")}
            data-confirm={gettext("Delete this type? Materials keep existing without it.")}
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
    type = Inventory.get_material_type!(id)
    {:ok, _} = Inventory.delete_material_type(type)

    {:noreply,
     socket |> put_flash(:info, gettext("Type deleted.")) |> stream_delete(:types, type)}
  end
end
