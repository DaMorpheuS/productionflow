defmodule ProductionflowWeb.Catalog.ProductTemplateLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.Catalog
  alias Productionflow.Catalog.ProductTemplate

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input
            field={@form[:output_unit]}
            type="text"
            label={gettext("Output unit (item, flyer, poster…)")}
            required
          />
          <.input field={@form[:sku]} type="text" label={gettext("SKU")} />
        </div>
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save product")}
          </.button>
          <.button navigate={cancel_path(@template)}>{gettext("Cancel")}</.button>
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
    template = %ProductTemplate{}

    socket
    |> assign(:page_title, gettext("New product"))
    |> assign(:template, template)
    |> assign_form(Catalog.change_product_template(template))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    template = Catalog.get_product_template!(id)

    socket
    |> assign(:page_title, gettext("Edit product"))
    |> assign(:template, template)
    |> assign_form(Catalog.change_product_template(template))
  end

  @impl true
  def handle_event("validate", %{"product_template" => params}, socket) do
    changeset = Catalog.change_product_template(socket.assigns.template, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"product_template" => params}, socket) do
    save_template(socket, socket.assigns.live_action, params)
  end

  defp save_template(socket, :new, params) do
    case Catalog.create_product_template(params) do
      {:ok, template} -> saved(socket, template, gettext("Product created."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_template(socket, :edit, params) do
    case Catalog.update_product_template(socket.assigns.template, params) do
      {:ok, template} -> saved(socket, template, gettext("Product updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, template, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/catalog/products/#{template}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "product_template"))
  end

  defp cancel_path(%ProductTemplate{id: nil}), do: ~p"/catalog/products"
  defp cancel_path(template), do: ~p"/catalog/products/#{template}"
end
