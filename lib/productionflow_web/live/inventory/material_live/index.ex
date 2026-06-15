defmodule ProductionflowWeb.Inventory.MaterialLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Materials"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "inventory.manage"))
     |> assign(:categories, Inventory.list_categories())
     |> assign(:filter, %{
       "search" => "",
       "category_id" => "",
       "low_stock" => "false",
       "include_archived" => "false"
     })
     |> stream(:materials, Inventory.list_materials())}
  end

  @impl true
  def handle_event("filter", %{"search" => _} = filter, socket) do
    materials =
      Inventory.list_materials(
        search: filter["search"],
        category_id: filter["category_id"],
        low_stock: filter["low_stock"] == "true",
        include_archived: filter["include_archived"] == "true"
      )

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:materials, materials, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Materials")}
        <:subtitle>{gettext("Stock, prices and suppliers.")}</:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/inventory/categories"}>
            {gettext("Categories")}
          </.button>
          <.button :if={@can_manage} variant="primary" navigate={~p"/inventory/materials/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New material")}
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} phx-change="filter" id="material-filters" class="flex flex-wrap gap-3">
        <input
          type="text"
          name="search"
          value={@filter["search"]}
          placeholder={gettext("Search name, SKU or supplier code")}
          phx-debounce="300"
          class="input"
        />
        <select name="category_id" class="select">
          <option value="" selected={@filter["category_id"] == ""}>
            {gettext("All categories")}
          </option>
          <option
            :for={c <- @categories}
            value={c.id}
            selected={@filter["category_id"] == to_string(c.id)}
          >
            {c.name}
          </option>
        </select>
        <label class="flex items-center gap-2 text-sm">
          <input type="hidden" name="low_stock" value="false" />
          <input
            type="checkbox"
            name="low_stock"
            value="true"
            checked={@filter["low_stock"] == "true"}
            class="checkbox checkbox-sm"
          /> {gettext("Low stock")}
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input type="hidden" name="include_archived" value="false" />
          <input
            type="checkbox"
            name="include_archived"
            value="true"
            checked={@filter["include_archived"] == "true"}
            class="checkbox checkbox-sm"
          /> {gettext("Show archived")}
        </label>
      </.form>

      <.table id="materials" rows={@streams.materials}>
        <:col :let={{_id, material}} label={gettext("Name")}>
          <.link navigate={~p"/inventory/materials/#{material}"} class="font-semibold hover:underline">
            {material.name}
          </.link>
          <span :if={material.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        </:col>
        <:col :let={{_id, material}} label={gettext("SKU")}>{material.sku}</:col>
        <:col :let={{_id, material}} label={gettext("Category")}>
          {material.category && material.category.name}
        </:col>
        <:col :let={{_id, material}} label={gettext("Stock")}>
          <span class={[Inventory.negative_stock?(material) && "text-error font-semibold"]}>
            {Decimal.to_string(material.current_stock)} {material.unit}
          </span>
          <span :if={Inventory.negative_stock?(material)} class="badge badge-error badge-sm ml-1">
            {gettext("Negative")}
          </span>
          <span :if={Inventory.low_stock?(material)} class="badge badge-warning badge-sm ml-1">
            {gettext("Low")}
          </span>
        </:col>
        <:col :let={{_id, material}} label={gettext("Cost")}>{money(material.cost_price)}</:col>
        <:col :let={{_id, material}} label={gettext("Sales")}>{money(material.sales_price)}</:col>
        <:action :let={{_id, material}}>
          <.link navigate={~p"/inventory/materials/#{material}"}>{gettext("View")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
