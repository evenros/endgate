defmodule EngineeringAnalyticsTerminal.DataProcessing.Supervisor do
  @moduledoc """
  Supervisor for data processing services.
  
  This supervisor manages data processing workers and ensures
  they are properly restarted in case of failures.
  """
  
  use Supervisor
  
  @impl true
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end
  
  @impl true
  def init(_init_args) do
    children = [
      # Data processing is stateless, so we don't need a worker process
      # Instead, we'll just ensure the module is available
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end