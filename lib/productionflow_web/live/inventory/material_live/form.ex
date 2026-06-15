defmodule ProductionflowWeb.Inventory.MaterialLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Inventory, CRM}
  alias Productionflow.Inventory.Material

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="material-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input field={@form[:unit]} type="text" label={gettext("Unit (pieces, m, kg…)")} required />
          <.input field={@form[:sku]} type="text" label={gettext("SKU / article code")} />
          <.input field={@form[:supplier_code]} type="text" label={gettext("Supplier article code")} />
          <.input
            field={@form[:supplier_id]}
            type="select"
            label={gettext("Supplier")}
            prompt={gettext("No supplier")}
            options={@supplier_options}
          />
          <.input
            field={@form[:category_id]}
            type="select"
            label={gettext("Category")}
            prompt={gettext("No category")}
            options={@category_options}
          />
          <.input
            field={@form[:cost_price]}
            type="number"
            step="0.01"
            label={gettext("Cost price (€)")}
          />
          <.input
            field={@form[:sales_price]}
            type="number"
            step="0.01"
            label={gettext("Sales price (€)")}
          />
          <.input
            field={@form[:minimum_stock]}
            type="number"
            step="0.01"
            label={gettext("Minimum stock")}
          />
          <.input
            :if={@live_action == :new}
            type="number"
            step="0.01"
            label={gettext("Opening stock")}
            id="material_opening_stock"
            name="material[opening_stock]"
            value={@opening_stock}
          />
        </div>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save material")}
          </.button>
          <.button navigate={cancel_path(@material)}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:supplier_options, supplier_options())
      |> assign(:category_options, category_options())
      |> assign(:opening_stock, "")

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    material = %Material{}

    socket
    |> assign(:page_title, gettext("New material"))
    |> assign(:material, material)
    |> assign_form(Inventory.change_material(material))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    material = Inventory.get_material!(id)

    socket
    |> assign(:page_title, gettext("Edit material"))
    |> assign(:material, material)
    |> assign_form(Inventory.change_material(material))
  end

  @impl true
  def handle_event("validate", %{"material" => params}, socket) do
    changeset = Inventory.change_material(socket.assigns.material, params)

    {:noreply,
     socket
     |> assign(:opening_stock, params["opening_stock"] || "")
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"material" => params}, socket) do
    save_material(socket, socket.assigns.live_action, params)
  end

  defp save_material(socket, :new, params) do
    case Inventory.create_material(params) do
      {:ok, material} -> saved(socket, material, gettext("Material created."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_material(socket, :edit, params) do
    case Inventory.update_material(socket.assigns.material, params) do
      {:ok, material} -> saved(socket, material, gettext("Material updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, material, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/inventory/materials/#{material}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "material"))
  end

  defp supplier_options do
    CRM.list_relations(type: :supplier) |> Enum.map(&{&1.name, &1.id})
  end

  defp category_options do
    Inventory.list_categories() |> Enum.map(&{&1.name, &1.id})
  end

  defp cancel_path(%Material{id: nil}), do: ~p"/inventory/materials"
  defp cancel_path(material), do: ~p"/inventory/materials/#{material}"
end
