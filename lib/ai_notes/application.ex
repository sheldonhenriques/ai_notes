defmodule AiNotes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AiNotesWeb.Telemetry,
      AiNotes.Repo,
      {DNSCluster, query: Application.get_env(:ai_notes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AiNotes.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: AiNotes.Finch},
      # Start a worker by calling: AiNotes.Worker.start_link(arg)
      # {AiNotes.Worker, arg},
      # Start to serve requests, typically the last entry
      AiNotesWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiNotes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AiNotesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
