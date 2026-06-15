defmodule ProductionflowWeb.Catalog.ProductTemplateLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Catalog
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Products"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "catalog.manage"))
     |> assign(:filter, %{"search" => "", "include_archived" => "false"})
     |> stream(:templates, Catalog.list_product_templates())}
  end

  @impl true
  def handle_event("filter", %{"search" => _} = filter, socket) do
    templates =
      Catalog.list_product_templates(
        search: filter["search"],
        include_archived: filter["include_archived"] == "true"
      )

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:templates, templates, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Products")}
        <:subtitle>
          {gettext("Product templates: a saved production route + bill of materials.")}
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} variant="primary" navigate={~p"/catalog/products/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New product")}
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} phx-change="filter" id="product-filters" class="flex flex-wrap gap-3">
        <input
          type="text"
          name="search"
          value={@filter["search"]}
          placeholder={gettext("Search name or SKU")}
          phx-debounce="300"
          class="input"
        />
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

      <.table id="templates" rows={@streams.templates}>
        <:col :let={{_id, template}} label={gettext("Name")}>
          <.link navigate={~p"/catalog/products/#{template}"} class="font-semibold hover:underline">
            {template.name}
          </.link>
          <span :if={template.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        </:col>
        <:col :let={{_id, template}} label={gettext("SKU")}>{template.sku}</:col>
        <:col :let={{_id, template}} label={gettext("Unit")}>{template.output_unit}</:col>
        <:action :let={{_id, template}}>
          <.link navigate={~p"/catalog/products/#{template}"}>{gettext("View")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
