defmodule ProductionflowWeb.Inventory.MaterialTypeLive.Show do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    type = Inventory.get_material_type!(id)

    {:ok,
     socket
     |> assign(:page_title, type.name)
     |> assign(:type, type)
     |> stream(:fields, type.field_definitions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@type.name}
        <:subtitle>
          <.link navigate={~p"/inventory/types"} class="hover:underline">
            &larr; {gettext("All types")}
          </.link>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/inventory/types/#{@type}/edit"}>{gettext("Rename")}</.button>
          <.button variant="primary" navigate={~p"/inventory/types/#{@type}/fields/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("Add field")}
          </.button>
        </:actions>
      </.header>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Custom fields")}</h2>
        <ul id="fields" phx-update="stream" class="divide-y divide-base-200">
          <li id="fields-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No fields yet. Add one to capture extra data on materials of this type.")}
          </li>
          <li
            :for={{id, field} <- @streams.fields}
            id={id}
            class="flex items-center gap-4 py-2 text-sm"
          >
            <span class="flex-1">
              <span class="font-medium">{field.label}</span>
              <span class="text-base-content/50">({field.key})</span>
            </span>
            <span class="badge badge-sm">{field_type_label(field.field_type)}</span>
            <span :if={field.unit} class="text-base-content/60">{field.unit}</span>
            <span :if={field.required} class="badge badge-warning badge-sm">{gettext("Required")}</span>
            <.link navigate={~p"/inventory/types/#{@type}/fields/#{field}/edit"}>{gettext("Edit")}</.link>
            <.link
              phx-click="delete_field"
              phx-value-id={field.id}
              data-confirm={gettext("Delete this field?")}
            >
              {gettext("Delete")}
            </.link>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("delete_field", %{"id" => id}, socket) do
    field = Inventory.get_field_definition!(id)
    {:ok, _} = Inventory.delete_field_definition(field)

    {:noreply,
     socket |> put_flash(:info, gettext("Field deleted.")) |> stream_delete(:fields, field)}
  end

  defp field_type_label(:text), do: gettext("Text")
  defp field_type_label(:number), do: gettext("Number")
  defp field_type_label(:boolean), do: gettext("Yes / No")
  defp field_type_label(:select), do: gettext("Dropdown")
end
