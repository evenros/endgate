defmodule EngineeringAnalyticsTerminal.CLI.Supervisor do
  @moduledoc """
  Supervisor for CLI interface.
  
  This supervisor manages the CLI GenServer process.
  """
  
  use Supervisor
  
  @impl true
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end
  
  @impl true
  def init(_init_args) do
    children = [
      # CLI worker - we want this to restart if it crashes
      worker(EngineeringAnalyticsTerminal.CLI, [], restart: :transient)
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end