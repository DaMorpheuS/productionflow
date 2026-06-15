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
            field={@form[:material_type_id]}
            type="select"
            label={gettext("Material type")}
            prompt={gettext("No type")}
            options={@type_options}
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

        <fieldset :if={@field_definitions != []} class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Type details")}</legend>
          <div class="mt-2 grid gap-4 sm:grid-cols-2">
            <.custom_field
              :for={definition <- @field_definitions}
              definition={definition}
              value={Map.get(@attributes_input, definition.key)}
              errors={attribute_errors(@form, definition.key)}
            />
          </div>
        </fieldset>

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

  attr :definition, :map, required: true
  attr :value, :any, default: nil
  attr :errors, :list, default: []

  defp custom_field(%{definition: %{field_type: :boolean}} = assigns) do
    ~H"""
    <.input
      type="checkbox"
      name={"material[attributes][#{@definition.key}]"}
      id={"material_attr_#{@definition.key}"}
      label={@definition.label}
      checked={@value in [true, "true", "on"]}
      errors={@errors}
    />
    """
  end

  defp custom_field(%{definition: %{field_type: :select}} = assigns) do
    ~H"""
    <.input
      type="select"
      name={"material[attributes][#{@definition.key}]"}
      id={"material_attr_#{@definition.key}"}
      label={custom_label(@definition)}
      prompt={gettext("Choose...")}
      options={@definition.options}
      value={@value}
      errors={@errors}
    />
    """
  end

  defp custom_field(assigns) do
    assigns =
      assign(
        assigns,
        :input_type,
        if(assigns.definition.field_type == :number, do: "number", else: "text")
      )

    ~H"""
    <.input
      type={@input_type}
      step={@input_type == "number" && "any"}
      name={"material[attributes][#{@definition.key}]"}
      id={"material_attr_#{@definition.key}"}
      label={custom_label(@definition)}
      value={@value}
      errors={@errors}
    />
    """
  end

  defp custom_label(%{label: label, unit: nil}), do: label
  defp custom_label(%{label: label, unit: ""}), do: label
  defp custom_label(%{label: label, unit: unit}), do: "#{label} (#{unit})"

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:supplier_options, supplier_options())
      |> assign(:category_options, category_options())
      |> assign(:type_options, type_options())
      |> assign(:opening_stock, "")

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    material = %Material{}
    definitions = []

    socket
    |> assign(:page_title, gettext("New material"))
    |> assign(:material, material)
    |> assign(:field_definitions, definitions)
    |> assign(:attributes_input, %{})
    |> assign_form(Inventory.change_material(material, %{}, definitions))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    material = Inventory.get_material!(id)
    definitions = Inventory.field_definitions_for(material.material_type_id)

    socket
    |> assign(:page_title, gettext("Edit material"))
    |> assign(:material, material)
    |> assign(:field_definitions, definitions)
    |> assign(:attributes_input, material.attributes || %{})
    |> assign_form(Inventory.change_material(material, %{}, definitions))
  end

  @impl true
  def handle_event("validate", %{"material" => params}, socket) do
    definitions = Inventory.field_definitions_for(blank_to_nil(params["material_type_id"]))
    attributes = prefill_defaults(params["attributes"] || %{}, definitions)
    params = Map.put(params, "attributes", attributes)
    changeset = Inventory.change_material(socket.assigns.material, params, definitions)

    {:noreply,
     socket
     |> assign(:field_definitions, definitions)
     |> assign(:attributes_input, attributes)
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

  defp type_options do
    Inventory.list_material_types() |> Enum.map(&{&1.name, &1.id})
  end

  # Fills empty custom fields with their definition default value.
  defp prefill_defaults(attributes, definitions) do
    Enum.reduce(definitions, attributes, fn definition, acc ->
      current = Map.get(acc, definition.key)

      if current in [nil, ""] and definition.default_value not in [nil, ""],
        do: Map.put(acc, definition.key, definition.default_value),
        else: acc
    end)
  end

  defp attribute_errors(form, key) do
    for {:attributes, {msg, opts}} <- form.source.errors, opts[:key] == key, do: msg
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp cancel_path(%Material{id: nil}), do: ~p"/inventory/materials"
  defp cancel_path(material), do: ~p"/inventory/materials/#{material}"
end
