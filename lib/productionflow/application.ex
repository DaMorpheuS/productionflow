defmodule Productionflow.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ProductionflowWeb.Telemetry,
      Productionflow.Repo,
      {DNSCluster, query: Application.get_env(:productionflow, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Productionflow.PubSub},
      # Start a worker by calling: Productionflow.Worker.start_link(arg)
      # {Productionflow.Worker, arg},
      # Start to serve requests, typically the last entry
      ProductionflowWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Productionflow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ProductionflowWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
