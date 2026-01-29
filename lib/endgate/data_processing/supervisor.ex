defmodule Endgate.DataProcessing.Supervisor do
  @moduledoc """
  Supervisor for the data processing components.
  
  This supervisor manages the data processing pipeline and related workers.
  """
  
  use Supervisor
  
  require Logger
  
  # Supervisor child specification
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  # Supervisor lifecycle
  def start_link(opts \ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("Starting Data Processing Supervisor")
    
    children = [
      # Start the main data processing pipeline
      Endgate.DataProcessing.Pipeline,
      
      # Additional data processing workers would be added here
      # For example:
      # Endgate.DataProcessing.AISProcessor,
      # Endgate.DataProcessing.MetProcessor,
      # Endgate.DataProcessing.ValidationWorker
    ]
    
    # Start the supervision tree
    opts = [strategy: :one_for_one, name: Endgate.DataProcessing.Supervisor]
    Supervisor.init(children, opts)
  end
  
  # Configuration change handler
  def config_change(changed, removed) do
    # Propagate configuration changes to child processes
    Supervisor.which_children(__MODULE__)
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      case Process.info(pid, :registered_name) do
        [:registered_name, name] ->
          try do
            apply(name, :config_change, [changed, removed])
          rescue
            _ -> :ok
          end
        _ -> :ok
      end
    end)
    
    :ok
  end
  
  # Public API for accessing child processes
  def get_pipeline() do
    Endgate.DataProcessing.Pipeline
  end
  
  def process_data(data) do
    Endgate.DataProcessing.Pipeline.process_data(data)
  end
  
  def get_metrics() do
    Endgate.DataProcessing.Pipeline.get_metrics()
  end
  
  def clear_cache() do
    Endgate.DataProcessing.Pipeline.clear_cache()
  end
end