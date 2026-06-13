defmodule ProductionflowWeb.DashboardLive do
  use ProductionflowWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Dashboard"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Welcome back")}
        <:subtitle>{@current_scope.user.email}</:subtitle>
      </.header>

      <div class="rounded-xl border border-base-300 bg-base-100 p-6">
        <p class="text-base-content/70">
          {gettext("Your production workspace will appear here as we build it out.")}
        </p>
      </div>
    </Layouts.app>
    """
  end
end
