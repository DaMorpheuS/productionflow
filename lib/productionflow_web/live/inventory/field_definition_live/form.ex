defmodule ProductionflowWeb.Inventory.FieldDefinitionLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory
  alias Productionflow.Inventory.FieldDefinition

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@type.name}</:subtitle>
      </.header>

      <.form for={@form} id="field-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:label]} type="text" label={gettext("Label")} required />
          <.input
            field={@form[:key]}
            type="text"
            label={gettext("Key (lowercase, no spaces)")}
            required
          />
          <.input
            field={@form[:field_type]}
            type="select"
            label={gettext("Field type")}
            options={field_type_options()}
          />
          <.input field={@form[:unit]} type="text" label={gettext("Unit (optional, e.g. mm, g/m²)")} />
        </div>

        <.input
          :if={@field_type == "select"}
          type="text"
          name="field_definition[options]"
          id="field_definition_options"
          value={@options_text}
          label={gettext("Dropdown options (comma separated)")}
        />

        <div class="mt-4 grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:default_value]}
            type="text"
            label={gettext("Default value (optional)")}
          />
          <.input field={@form[:position]} type="number" label={gettext("Position")} />
        </div>
        <.input field={@form[:required]} type="checkbox" label={gettext("Required")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save field")}
          </.button>
          <.button navigate={~p"/inventory/types/#{@type}"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => type_id} = params, _session, socket) do
    type = Inventory.get_material_type!(type_id)
    socket = assign(socket, :type, type)
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    definition = %FieldDefinition{}

    socket
    |> assign(:page_title, gettext("New field"))
    |> assign(:definition, definition)
    |> assign(:field_type, "text")
    |> assign(:options_text, "")
    |> assign_form(Inventory.change_field_definition(definition))
  end

  defp apply_action(socket, :edit, %{"field_id" => field_id}) do
    definition = Inventory.get_field_definition!(field_id)

    socket
    |> assign(:page_title, gettext("Edit field"))
    |> assign(:definition, definition)
    |> assign(:field_type, to_string(definition.field_type))
    |> assign(:options_text, Enum.join(definition.options, ", "))
    |> assign_form(Inventory.change_field_definition(definition))
  end

  @impl true
  def handle_event("validate", %{"field_definition" => params}, socket) do
    changeset = Inventory.change_field_definition(socket.assigns.definition, params)

    {:noreply,
     socket
     |> assign(:field_type, params["field_type"] || socket.assigns.field_type)
     |> assign(:options_text, params["options"] || socket.assigns.options_text)
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"field_definition" => params}, socket) do
    save_field(socket, socket.assigns.live_action, params)
  end

  defp save_field(socket, :new, params) do
    case Inventory.create_field_definition(socket.assigns.type, params) do
      {:ok, _field} -> saved(socket, gettext("Field added."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_field(socket, :edit, params) do
    case Inventory.update_field_definition(socket.assigns.definition, params) do
      {:ok, _field} -> saved(socket, gettext("Field updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/inventory/types/#{socket.assigns.type}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "field_definition"))
  end

  defp field_type_options do
    Enum.map(FieldDefinition.field_types(), fn type ->
      {Phoenix.Naming.humanize(type), type}
    end)
  end
end
