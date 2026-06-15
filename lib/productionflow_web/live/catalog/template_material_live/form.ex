defmodule ProductionflowWeb.Catalog.TemplateMaterialLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Catalog, Inventory}
  alias Productionflow.Catalog.TemplateMaterial

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@template.name}</:subtitle>
      </.header>

      <.form for={@form} id="template-material-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:material_id]}
          type="select"
          label={gettext("Material")}
          prompt={gettext("Choose a material")}
          options={@material_options}
          required
        />
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:quantity_per_unit]}
            type="number"
            step="any"
            label={gettext("Quantity per product unit")}
            required
          />
          <.input field={@form[:waste_pct]} type="number" step="any" label={gettext("Waste %")} />
        </div>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save material")}
          </.button>
          <.button navigate={~p"/catalog/products/#{@template}"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => template_id} = params, _session, socket) do
    template = Catalog.get_product_template!(template_id)

    socket =
      socket
      |> assign(:template, template)
      |> assign(:material_options, material_options())

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    line = %TemplateMaterial{}

    socket
    |> assign(:page_title, gettext("Add material"))
    |> assign(:line, line)
    |> assign_form(Catalog.change_template_material(line))
  end

  defp apply_action(socket, :edit, %{"material_id" => id}) do
    line = Catalog.get_template_material!(id)

    socket
    |> assign(:page_title, gettext("Edit material"))
    |> assign(:line, line)
    |> assign_form(Catalog.change_template_material(line))
  end

  @impl true
  def handle_event("validate", %{"template_material" => params}, socket) do
    changeset = Catalog.change_template_material(socket.assigns.line, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"template_material" => params}, socket) do
    save_line(socket, socket.assigns.live_action, params)
  end

  defp save_line(socket, :new, params) do
    case Catalog.add_template_material(socket.assigns.template, params) do
      {:ok, _line} -> saved(socket, gettext("Material added."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_line(socket, :edit, params) do
    case Catalog.update_template_material(socket.assigns.line, params) do
      {:ok, _line} -> saved(socket, gettext("Material updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/catalog/products/#{socket.assigns.template}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "template_material"))
  end

  defp material_options do
    Inventory.list_materials() |> Enum.map(&{"#{&1.name} (#{&1.unit})", &1.id})
  end
end
