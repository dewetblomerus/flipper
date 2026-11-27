defmodule Flipper.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Flipper.Workers.ImportDrafts

  @impl true
  def start(_type, _args) do
    children = [
      FlipperWeb.Telemetry,
      Flipper.Repo,
      {Phoenix.PubSub, name: Flipper.PubSub},
      Flipper.Ebay.Session,
      {Oban, Application.fetch_env!(:flipper, Oban)},
      # Imports the drafts list at boot, which also rejects a stale cookie.
      {Task, &queue_boot_import/0},
      {DNSCluster, query: Application.get_env(:flipper, :dns_cluster_query) || :ignore},
      # Start a worker by calling: Flipper.Worker.start_link(arg)
      # {Flipper.Worker, arg},
      # Start to serve requests, typically the last entry
      FlipperWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Flipper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FlipperWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp queue_boot_import do
    if Application.get_env(:flipper, :import_at_boot, true) do
      Oban.insert!(ImportDrafts.new(%{}))
    end
  end
end
