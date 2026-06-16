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

  # CRM / Relations. Read pages require crm.view; write pages require crm.manage.
  scope "/relations", ProductionflowWeb.CRM, as: :crm do
    pipe_through [:browser, :require_authenticated_user]

    # Declared before the `/:id` show route below so the static `/new` segment
    # is matched first (Phoenix matches routes in definition order).
    live_session :crm_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "crm.manage"}}
      ] do
      live "/new", RelationLive.Form, :new
      live "/:id/edit", RelationLive.Form, :edit
      live "/:id/addresses/new", AddressLive.Form, :new
      live "/:id/addresses/:address_id/edit", AddressLive.Form, :edit
      live "/:id/contacts/new", ContactLive.Form, :new
      live "/:id/contacts/:contact_id/edit", ContactLive.Form, :edit
    end

    live_session :crm,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "crm.view"}}
      ] do
      live "/", RelationLive.Index, :index
      live "/:id", RelationLive.Show, :show
    end
  end

  # Production resources. Read pages require production.view; write pages require
  # production.manage. Manage session declared first so static routes
  # (/machines/new, /settings) win over /machines/:id.
  scope "/production", ProductionflowWeb.Production, as: :production do
    pipe_through [:browser, :require_authenticated_user]

    live_session :production_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "production.manage"}}
      ] do
      live "/machines/new", MachineLive.Form, :new
      live "/machines/:id/edit", MachineLive.Form, :edit
      live "/settings", ProductionSettingsLive, :edit
    end

    live_session :production,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "production.view"}}
      ] do
      live "/machines", MachineLive.Index, :index
      live "/machines/:id", MachineLive.Show, :show
    end
  end

  # Inventory. Read pages require inventory.view; material management requires
  # inventory.manage; booking stock movements requires inventory.book (events on
  # the material show page). Manage session first so static routes win.
  scope "/inventory", ProductionflowWeb.Inventory, as: :inventory do
    pipe_through [:browser, :require_authenticated_user]

    live_session :inventory_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "inventory.manage"}}
      ] do
      live "/materials/new", MaterialLive.Form, :new
      live "/materials/:id/edit", MaterialLive.Form, :edit
      live "/categories", CategoryLive.Index, :index
      live "/types", MaterialTypeLive.Index, :index
      live "/types/new", MaterialTypeLive.Form, :new
      live "/types/:id/edit", MaterialTypeLive.Form, :edit
      live "/types/:id/fields/new", FieldDefinitionLive.Form, :new
      live "/types/:id/fields/:field_id/edit", FieldDefinitionLive.Form, :edit
      live "/types/:id", MaterialTypeLive.Show, :show
    end

    live_session :inventory,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "inventory.view"}}
      ] do
      live "/materials", MaterialLive.Index, :index
      live "/materials/:id", MaterialLive.Show, :show
    end
  end

  # Catalog. Product templates (route + bill of materials). Manage session first
  # so static routes win over /products/:id.
  scope "/catalog", ProductionflowWeb.Catalog, as: :catalog do
    pipe_through [:browser, :require_authenticated_user]

    live_session :catalog_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "catalog.manage"}}
      ] do
      live "/products/new", ProductTemplateLive.Form, :new
      live "/products/:id/edit", ProductTemplateLive.Form, :edit
      live "/products/:id/steps/new", RouteStepLive.Form, :new
      live "/products/:id/steps/:step_id/edit", RouteStepLive.Form, :edit
      live "/products/:id/materials/new", TemplateMaterialLive.Form, :new
      live "/products/:id/materials/:material_id/edit", TemplateMaterialLive.Form, :edit
    end

    live_session :catalog,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "catalog.view"}}
      ] do
      live "/products", ProductTemplateLive.Index, :index
      live "/products/:id", ProductTemplateLive.Show, :show
    end
  end

  scope "/pricing", ProductionflowWeb.Pricing, as: :pricing do
    pipe_through [:browser, :require_authenticated_user]

    live_session :pricing_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "pricing.manage"}}
      ] do
      live "/settings", PricingSettingsLive, :edit
    end

    live_session :pricing,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "pricing.view"}}
      ] do
      live "/quote", QuoteLive, :index
    end
  end

  scope "/orders", ProductionflowWeb.Orders, as: :orders do
    pipe_through [:browser, :require_authenticated_user]

    live_session :orders_manage,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "orders.manage"}}
      ] do
      live "/new", OrderLive.Form, :new
      live "/settings", OrderSettingsLive, :edit
      live "/:id/edit", OrderLive.Form, :edit
    end

    live_session :orders,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "orders.view"}}
      ] do
      live "/", OrderLive.Index, :index
      live "/:id", OrderLive.Show, :show
      live "/:id/lines/:line_id", OrderLineLive.Show, :show
    end
  end

  scope "/quotes", ProductionflowWeb.Orders, as: :quotes do
    pipe_through [:browser, :require_authenticated_user]

    live_session :quotes,
      on_mount: [
        {ProductionflowWeb.UserAuth, :require_authenticated},
        {ProductionflowWeb.UserAuth, {:require_permission, "orders.view"}}
      ] do
      live "/", OrderLive.Index, :quotes
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
