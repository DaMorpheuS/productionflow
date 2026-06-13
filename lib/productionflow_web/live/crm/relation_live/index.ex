defmodule ProductionflowWeb.CRM.RelationLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.CRM
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Relations"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "crm.manage"))
     |> assign(:filter, %{"search" => "", "type" => "", "include_archived" => "false"})
     |> stream(:relations, list_relations(%{}))}
  end

  @impl true
  def handle_event("filter", %{"search" => _, "type" => _} = filter, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:relations, list_relations(filter), reset: true)}
  end

  defp list_relations(filter) do
    CRM.list_relations(
      search: filter["search"],
      type: parse_type(filter["type"]),
      include_archived: filter["include_archived"] == "true"
    )
  end

  defp parse_type("customer"), do: :customer
  defp parse_type("supplier"), do: :supplier
  defp parse_type("prospect"), do: :prospect
  defp parse_type(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Relations")}
        <:subtitle>{gettext("Customers, suppliers and prospects.")}</:subtitle>
        <:actions>
          <.button :if={@can_manage} variant="primary" navigate={~p"/relations/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New relation")}
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} phx-change="filter" id="relation-filters" class="flex flex-wrap gap-3">
        <input
          type="text"
          name="search"
          value={@filter["search"]}
          placeholder={gettext("Search name or code")}
          phx-debounce="300"
          class="input"
        />
        <select name="type" class="select">
          <option value="" selected={@filter["type"] == ""}>{gettext("All types")}</option>
          <option value="customer" selected={@filter["type"] == "customer"}>
            {gettext("Customers")}
          </option>
          <option value="supplier" selected={@filter["type"] == "supplier"}>
            {gettext("Suppliers")}
          </option>
          <option value="prospect" selected={@filter["type"] == "prospect"}>
            {gettext("Prospects")}
          </option>
        </select>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="hidden"
            name="include_archived"
            value="false"
          />
          <input
            type="checkbox"
            name="include_archived"
            value="true"
            checked={@filter["include_archived"] == "true"}
            class="checkbox checkbox-sm"
          /> {gettext("Show archived")}
        </label>
      </.form>

      <.table id="relations" rows={@streams.relations}>
        <:col :let={{_id, relation}} label={gettext("Name")}>
          <.link navigate={~p"/relations/#{relation}"} class="font-semibold hover:underline">
            {relation.name}
          </.link>
          <span :if={relation.archived_at} class="badge badge-ghost ml-2">
            {gettext("Archived")}
          </span>
        </:col>
        <:col :let={{_id, relation}} label={gettext("Code")}>{relation.code}</:col>
        <:col :let={{_id, relation}} label={gettext("Type")}>
          <.type_badges relation={relation} />
        </:col>
        <:col :let={{_id, relation}} label={gettext("Email")}>{relation.email}</:col>
        <:col :let={{_id, relation}} label={gettext("Phone")}>{relation.phone}</:col>
        <:action :let={{_id, relation}}>
          <.link navigate={~p"/relations/#{relation}"}>{gettext("View")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  attr :relation, :map, required: true

  def type_badges(assigns) do
    ~H"""
    <span class="flex flex-wrap gap-1">
      <span :if={@relation.is_customer} class="badge badge-primary">{gettext("Customer")}</span>
      <span :if={@relation.is_supplier} class="badge badge-secondary">{gettext("Supplier")}</span>
      <span :if={@relation.is_prospect} class="badge badge-accent">{gettext("Prospect")}</span>
    </span>
    """
  end
end
