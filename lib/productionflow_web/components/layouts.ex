defmodule ProductionflowWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ProductionflowWeb, :html

  alias Productionflow.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :page_title, :string, default: nil, doc: "the title shown in the page header"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-base-200">
      <.sidebar current_scope={@current_scope} />

      <div class="flex-1 flex flex-col min-w-0">
        <header class="flex items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 py-3 sm:px-6 lg:px-8">
          <h1 class="text-lg font-semibold truncate">{@page_title || gettext("Productionflow")}</h1>
          <div class="flex items-center gap-3">
            <.theme_toggle />
            <div :if={@current_scope} class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                {@current_scope.user.email}
                <.icon name="hero-chevron-down-micro" class="size-4" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu z-10 mt-2 w-48 rounded-box bg-base-100 p-2 shadow"
              >
                <li>
                  <.link navigate={~p"/users/settings"}>{gettext("Settings")}</.link>
                </li>
                <li>
                  <.link href={~p"/users/log-out"} method="delete">{gettext("Log out")}</.link>
                </li>
              </ul>
            </div>
          </div>
        </header>

        <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-5xl space-y-6">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, default: nil

  defp sidebar(assigns) do
    ~H"""
    <aside class="hidden w-60 shrink-0 flex-col border-r border-base-300 bg-base-100 sm:flex">
      <div class="flex items-center gap-2 px-5 py-4">
        <img src={~p"/images/logo.svg"} width="32" alt="Productionflow" />
        <span class="text-base font-semibold">Productionflow</span>
      </div>

      <nav class="flex-1 space-y-1 px-3 py-2">
        <.nav_link navigate={~p"/"} icon="hero-home">{gettext("Dashboard")}</.nav_link>
        <.nav_link
          :if={Scope.can?(@current_scope, "crm.view")}
          navigate={~p"/relations"}
          icon="hero-identification"
        >
          {gettext("Relations")}
        </.nav_link>
        <.nav_link
          :if={Scope.can?(@current_scope, "production.view")}
          navigate={~p"/production/machines"}
          icon="hero-cog-6-tooth"
        >
          {gettext("Machines")}
        </.nav_link>

        <div
          :if={Scope.admin?(@current_scope)}
          class="px-3 pb-1 pt-4 text-xs font-semibold uppercase tracking-wide text-base-content/50"
        >
          {gettext("Administration")}
        </div>
        <.nav_link
          :if={Scope.can?(@current_scope, "admin.users")}
          navigate={~p"/admin/users"}
          icon="hero-users"
        >
          {gettext("Users")}
        </.nav_link>
        <.nav_link
          :if={Scope.can?(@current_scope, "admin.roles")}
          navigate={~p"/admin/roles"}
          icon="hero-shield-check"
        >
          {gettext("Roles")}
        </.nav_link>
      </nav>
    </aside>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-base-content/80 hover:bg-base-200 hover:text-base-content"
    >
      <.icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
