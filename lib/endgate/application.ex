defmodule Endgate.Application do
  @moduledoc """
  The main application module for the Endgate data analytics platform.
  
  This module is responsible for starting and supervising all the major
  components of the application including:
  - API clients (Barentswatch)
  - Data processing pipelines
  - Background workers
  - Web interface (when enabled)
  - CLI interface
  """
  
  use Application
  
  @impl true
  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the Ecto repository (will be added when we implement data storage)
      # Endgate.Repo,
      
      # Start the configuration manager
      Endgate.ConfigManager,
      
      # Start the centralized cache system
      Endgate.Cache,
      
      # Start the comprehensive logging system
      Endgate.Logger,
      
      # Start the health check and monitoring system
      Endgate.HealthCheck,
      
      # Start the Barentswatch API client
      Endgate.Barentswatch.Client,
      
      # Start the data processing supervisor
      Endgate.DataProcessing.Supervisor,
      
      # Start the real-time data broadcaster
      Endgate.Realtime.Broadcaster,
      
      # Start the background worker supervisor
      {Oban, 
       application: :endgate,
       repo: Endgate.Repo,  # Will be implemented
       plugins: [Oban.Plugins.Pruner],
       queues: [default: 10, data_sync: 10, reports: 5],
       name: Endgate.Workers}
    ]
    
    # Start the supervision tree
    opts = [strategy: :one_for_one, name: Endgate.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  @impl true
  def config_change(changed, _new, removed) do
    # Propagate configuration changes to all components
    Endgate.ConfigManager.config_change(changed, removed)
    Endgate.Cache.config_change(changed, removed)
    Endgate.Logger.config_change(changed, removed)
    Endgate.HealthCheck.config_change(changed, removed)
    Endgate.Barentswatch.Client.config_change(changed, removed)
    Endgate.DataProcessing.Supervisor.config_change(changed, removed)
    Endgate.Realtime.Broadcaster.config_change(changed, removed)
    :ok
  end
end