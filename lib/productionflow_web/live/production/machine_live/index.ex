defmodule ProductionflowWeb.Production.MachineLive.Index do
  use ProductionflowWeb, :live_view

  alias Productionflow.Production
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Machines"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "production.manage"))
     |> assign(:filter, %{"search" => "", "include_archived" => "false"})
     |> stream(:machines, Production.list_machines())}
  end

  @impl true
  def handle_event("filter", %{"search" => _} = filter, socket) do
    machines =
      Production.list_machines(
        search: filter["search"],
        include_archived: filter["include_archived"] == "true"
      )

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:machines, machines, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Machines")}
        <:subtitle>{gettext("Your machine park, with derived hourly cost.")}</:subtitle>
        <:actions>
          <.button :if={@can_manage} variant="primary" navigate={~p"/production/machines/new"}>
            <.icon name="hero-plus" class="size-4" /> {gettext("New machine")}
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} phx-change="filter" id="machine-filters" class="flex flex-wrap gap-3">
        <input
          type="text"
          name="search"
          value={@filter["search"]}
          placeholder={gettext("Search machines")}
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

      <.table id="machines" rows={@streams.machines}>
        <:col :let={{_id, machine}} label={gettext("Name")}>
          <.link navigate={~p"/production/machines/#{machine}"} class="font-semibold hover:underline">
            {machine.name}
          </.link>
          <span :if={machine.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        </:col>
        <:col :let={{_id, machine}} label={gettext("Output unit")}>{machine.output_unit}</:col>
        <:col :let={{_id, machine}} label={gettext("Per hour")}>{machine.units_per_hour}</:col>
        <:col :let={{_id, machine}} label={gettext("Machine cost/hr")}>
          {money(Production.machine_cost_per_hour(machine))}
        </:col>
        <:action :let={{_id, machine}}>
          <.link navigate={~p"/production/machines/#{machine}"}>{gettext("View")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
