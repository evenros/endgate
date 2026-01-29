defmodule EngineeringAnalyticsTerminal.Application do
  @moduledoc false
  
  use Application
  
  @impl true
  def start(_type, _args) do
    children = [
      # Start the main BarentsWatch supervisor
      EngineeringAnalyticsTerminal.BarentsWatch.Supervisor,
      
      # Start the data processing supervisor
      EngineeringAnalyticsTerminal.DataProcessing.Supervisor,
      
      # Start the analytics supervisor
      EngineeringAnalyticsTerminal.Analytics.Supervisor,
      
      # Start the CLI interface
      EngineeringAnalyticsTerminal.CLI.Supervisor
    ]
    
    opts = [
      strategy: :one_for_one,
      name: EngineeringAnalyticsTerminal.Supervisor,
      max_restarts: 3,
      max_seconds: 5
    ]
    
    Supervisor.start_link(children, opts)
  end
  
  @impl true
  def config_change(changed, _new, removed) do
    {:ok, []}
  end
end