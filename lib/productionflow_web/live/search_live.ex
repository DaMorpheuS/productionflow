defmodule ProductionflowWeb.SearchLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Orders, CRM, Inventory, Catalog}
  alias Productionflow.Accounts.Scope

  @limit 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Search"), query: "", groups: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:groups, run_search(socket.assigns.current_scope, query))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/search?#{%{q: query}}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{gettext("Search")}</.header>

      <form id="search-form" phx-change="search" class="max-w-xl">
        <label class="input input-lg w-full">
          <.icon name="hero-magnifying-glass" class="size-5 opacity-60" />
          <input
            type="search"
            name="q"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder={gettext("Search orders, relations, materials, products…")}
            class="grow"
          />
        </label>
      </form>

      <div :for={group <- @groups} class="rounded-xl border border-base-300 bg-base-100 p-5">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/50">
          {group.label}
        </h2>
        <ul class="divide-y divide-base-200">
          <li :for={result <- group.results} class="py-2">
            <.link navigate={result.path} class="flex items-center gap-2 hover:underline">
              <span class="font-medium">{result.label}</span>
              <span :if={result.sublabel not in [nil, ""]} class="text-sm text-base-content/60">
                · {result.sublabel}
              </span>
            </.link>
          </li>
        </ul>
      </div>

      <p :if={@query != "" and @groups == []} class="text-sm text-base-content/60">
        {gettext("No matches for \"%{query}\".", query: @query)}
      </p>
      <p :if={@query == ""} class="text-sm text-base-content/60">
        {gettext("Type above to search across the system.")}
      </p>
    </Layouts.app>
    """
  end

  # Builds the visible result groups: one per area the scope may view, dropping
  # groups with no hits. Blank queries return nothing.
  defp run_search(scope, query) do
    case String.trim(query) do
      "" ->
        []

      term ->
        [
          group(scope, "orders.view", gettext("Orders & quotes"), fn ->
            Orders.list_orders(search: term) |> limit() |> Enum.map(&order_result/1)
          end),
          group(scope, "crm.view", gettext("Relations"), fn ->
            CRM.list_relations(search: term) |> limit() |> Enum.map(&relation_result/1)
          end),
          group(scope, "inventory.view", gettext("Materials"), fn ->
            Inventory.list_materials(search: term) |> limit() |> Enum.map(&material_result/1)
          end),
          group(scope, "catalog.view", gettext("Products"), fn ->
            Catalog.list_product_templates(search: term) |> limit() |> Enum.map(&product_result/1)
          end)
        ]
        |> Enum.reject(&(is_nil(&1) or &1.results == []))
    end
  end

  defp group(scope, permission, label, fun) do
    if Scope.can?(scope, permission), do: %{label: label, results: fun.()}
  end

  defp limit(list), do: Enum.take(list, @limit)

  defp order_result(order) do
    %{
      label: order.number || order.quote_number,
      sublabel: order.relation.name,
      path: ~p"/orders/#{order}"
    }
  end

  defp relation_result(relation) do
    %{label: relation.name, sublabel: relation_types(relation), path: ~p"/relations/#{relation}"}
  end

  defp material_result(material) do
    %{label: material.name, sublabel: material.sku, path: ~p"/inventory/materials/#{material}"}
  end

  defp product_result(template) do
    %{label: template.name, sublabel: template.sku, path: ~p"/catalog/products/#{template}"}
  end

  defp relation_types(relation) do
    [
      {relation.is_customer, gettext("Customer")},
      {relation.is_supplier, gettext("Supplier")},
      {relation.is_prospect, gettext("Prospect")}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map_join(", ", &elem(&1, 1))
  end
end
