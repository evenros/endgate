defmodule EngineeringAnalyticsTerminal.BarentsWatch.Supervisor do
  @moduledoc """
  Supervisor for BarentsWatch API client and related services.
  
  This supervisor manages the BarentsWatch API client GenServer
  and any specialized API service workers.
  """
  
  use Supervisor
  
  @impl true
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end
  
  @impl true
  def init(_init_args) do
    children = [
      # Start the main BarentsWatch client
      worker(EngineeringAnalyticsTerminal.BarentsWatch.Client, [], restart: :transient),
      
      # Add specialized API workers here as needed
      # worker(EngineeringAnalyticsTerminal.BarentsWatch.WeatherWorker, [], restart: :transient),
      # worker(EngineeringAnalyticsTerminal.BarentsWatch.AISWorker, [], restart: :transient)
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end