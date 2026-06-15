defmodule ProductionflowWeb.Inventory.MaterialTypeLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory
  alias Productionflow.Inventory.MaterialType

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="type-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} required />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save type")}
          </.button>
          <.button navigate={cancel_path(@type)}>{gettext("Cancel")}</.button>
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
    type = %MaterialType{}

    socket
    |> assign(:page_title, gettext("New material type"))
    |> assign(:type, type)
    |> assign_form(Inventory.change_material_type(type))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    type = Inventory.get_material_type!(id)

    socket
    |> assign(:page_title, gettext("Edit material type"))
    |> assign(:type, type)
    |> assign_form(Inventory.change_material_type(type))
  end

  @impl true
  def handle_event("validate", %{"material_type" => params}, socket) do
    changeset = Inventory.change_material_type(socket.assigns.type, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"material_type" => params}, socket) do
    save_type(socket, socket.assigns.live_action, params)
  end

  defp save_type(socket, :new, params) do
    case Inventory.create_material_type(params) do
      {:ok, type} -> saved(socket, type, gettext("Type created."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_type(socket, :edit, params) do
    case Inventory.update_material_type(socket.assigns.type, params) do
      {:ok, type} -> saved(socket, type, gettext("Type updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, type, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/inventory/types/#{type}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "material_type"))
  end

  defp cancel_path(%MaterialType{id: nil}), do: ~p"/inventory/types"
  defp cancel_path(type), do: ~p"/inventory/types/#{type}"
end
