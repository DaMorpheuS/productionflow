defmodule ProductionflowWeb.Router do
  use ProductionflowWeb, :router

  import ProductionflowWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ProductionflowWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", ProductionflowWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:productionflow, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ProductionflowWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ProductionflowWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ProductionflowWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # Administration. Each section sits in its own live_session so the matching
  # permission can be enforced via an on_mount hook.
  scope "/admin", ProductionflowWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin_roles,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "admin.roles"}}
      ] do
      live "/roles", RoleLive.Index, :index
      live "/roles/new", RoleLive.Form, :new
      live "/roles/:id/edit", RoleLive.Form, :edit
    end

    live_session :admin_users,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "admin.users"}}
      ] do
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Form, :new
      live "/users/:id/edit", UserLive.Form, :edit
    end
  end

  scope "/", ProductionflowWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ProductionflowWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
