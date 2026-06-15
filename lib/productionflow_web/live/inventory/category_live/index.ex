defmodule ProductionflowWeb.Inventory.CategoryLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory
  alias Productionflow.Inventory.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Categories"))
     |> assign_form(Inventory.change_category(%Category{}))
     |> stream(:categories, Inventory.list_categories())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Material categories")}
        <:subtitle>
          <.link navigate={~p"/inventory/materials"} class="hover:underline">
            &larr; {gettext("Back to materials")}
          </.link>
        </:subtitle>
      </.header>

      <.form for={@form} id="category-form" phx-submit="create" class="mb-4 flex items-end gap-2">
        <.input field={@form[:name]} type="text" label={gettext("New category")} />
        <.button variant="primary">{gettext("Add")}</.button>
      </.form>

      <ul id="categories" phx-update="stream" class="divide-y divide-base-200">
        <li id="categories-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
          {gettext("No categories yet.")}
        </li>
        <li :for={{id, category} <- @streams.categories} id={id} class="flex items-center gap-4 py-2">
          <span class="flex-1 text-sm">{category.name}</span>
          <.link
            phx-click="delete"
            phx-value-id={category.id}
            data-confirm={gettext("Delete this category? Materials keep existing without it.")}
            class="text-sm"
          >
            {gettext("Delete")}
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create", %{"category" => params}, socket) do
    case Inventory.create_category(params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> assign_form(Inventory.change_category(%Category{}))
         |> stream_insert(:categories, category)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = Inventory.get_category!(id)
    {:ok, _} = Inventory.delete_category(category)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Category deleted."))
     |> stream_delete(:categories, category)}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "category"))
  end
end
