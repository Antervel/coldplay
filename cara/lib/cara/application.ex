defmodule Cara.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CaraWeb.Telemetry,
      Cara.Repo,
      {DNSCluster, query: Application.get_env(:cara, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cara.PubSub},
      # Start a worker by calling: Cara.Worker.start_link(arg)
      # {Cara.Worker, arg},
      # Start to serve requests, typically the last entry
      CaraWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cara.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CaraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
