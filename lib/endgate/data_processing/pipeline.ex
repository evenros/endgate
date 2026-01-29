defmodule Endgate.DataProcessing.Pipeline do
  @moduledoc """
  Multi-stage data processing pipeline using GenStage.
  
  This pipeline handles the ingestion, validation, transformation, and enrichment
  of data from various sources including the Barentswatch API.
  """
  
  use GenStage
  
  require Logger
  
  # Pipeline configuration
  @batch_size Application.get_env(:endgate, [:data_processing, :batch_size]) || 100
  @max_demand Application.get_env(:endgate, [:data_processing, :max_demand]) || 1000
  @cache_ttl Application.get_env(:endgate, [:data_processing, :cache_ttl]) || 3600
  
  # Public API - Child specification for supervision tree
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 5000
    }
  end
  
  # Pipeline lifecycle
  def start_link(opts \ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(:producer_consumer) do
    Logger.info("Starting Data Processing Pipeline")
    
    state = %{
      cache: %{},
      metrics: %{
        processed: 0,
        errors: 0,
        last_processed: nil
      },
      config: Application.get_all_env(:endgate)
    }
    
    {:producer_consumer, state, []}
  end
  
  # Public API methods
  def process_data(data) do
    GenStage.cast(__MODULE__, {:process, data})
  end
  
  def get_metrics() do
    GenStage.call(__MODULE__, :get_metrics)
  end
  
  def clear_cache() do
    GenStage.cast(__MODULE__, :clear_cache)
  end
  
  def config_change(changed, removed) do
    GenStage.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenStage callbacks
  @impl true
  def handle_demand(demand, state) do
    # When downstream consumers request data, we can fetch from source
    # For now, we'll just acknowledge the demand
    events = []
    {:noreply, events, state}
  end
  
  @impl true
  def handle_events(events, _from, state) do
    # Process incoming events through the pipeline stages
    processed_events = Enum.flat_map(events, &process_through_pipeline(&1, state))
    
    # Update metrics
    updated_state = update_metrics(state, length(events), length(processed_events))
    
    {:noreply, processed_events, updated_state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  @impl true
  def handle_cast({:process, data}, state) do
    # Process individual data items
    case process_through_pipeline(data, state) do
      [processed_data | _] ->
        updated_state = update_metrics(state, 1, 1)
        {:noreply, [], updated_state}
      [] ->
        updated_state = update_metrics(state, 1, 0)
        {:noreply, [], updated_state}
    end
  end
  
  @impl true
  def handle_cast(:clear_cache, state) do
    updated_state = %{state | cache: %{}}
    Logger.info("Data Processing Pipeline cache cleared")
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_cast({:config_change, changed, removed}, state) do
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  # Private pipeline processing methods
  defp process_through_pipeline(data, state) do
    # Pipeline stages: validate -> transform -> enrich -> cache
    with {:ok, validated} <- validate_data(data, state),
         {:ok, transformed} <- transform_data(validated, state),
         {:ok, enriched} <- enrich_data(transformed, state),
         {:ok, cached} <- cache_data(enriched, state) do
      [cached]
    else
      error ->
        Logger.warn("Data processing failed: #{inspect(error)}")
        []
    end
  end
  
  defp validate_data(data, _state) do
    # Implement data validation logic
    # Check required fields, data types, business rules
    
    case data do
      %{} = map when is_map(map) ->
        # Basic validation - check for required fields
        required_fields = ["id", "timestamp", "source"]
        
        missing_fields = Enum.filter(required_fields, fn field ->
          not Map.has_key?(data, field)
        end)
        
        if missing_fields == [] do
          {:ok, data}
        else
          {:error, :missing_fields, missing_fields: missing_fields}
        end
      
      _ ->
        {:error, :invalid_data_type, expected: "map", got: data |> Map.from_struct() |> Map.keys()}
    end
  end
  
  defp transform_data(data, _state) do
    # Implement data transformation logic
    # Standardize formats, normalize values, convert units
    
    try do
      # Example transformations
      transformed = %{
        data
        | 
        # Standardize timestamp format
        timestamp: to_string(data["timestamp"]),
        
        # Convert numeric fields to consistent types
        value: String.to_float(data["value"]) if Map.has_key?(data, "value"),
        
        # Add processing metadata
        processed_at: System.system_time(:second),
        processed_by: "endgate_pipeline"
      }
      
      {:ok, transformed}
    rescue
      error ->
        {:error, :transformation_error, error: error}
    end
  end
  
  defp enrich_data(data, _state) do
    # Implement data enrichment logic
    # Add derived fields, calculate metrics, add contextual information
    
    try do
      enriched = %{
        data
        | 
        # Add derived fields
        data_quality: calculate_data_quality(data),
        
        # Add contextual information
        processing_stage: "enriched",
        
        # Calculate metrics if applicable
        normalized_value: normalize_value(data["value"]) if Map.has_key?(data, "value")
      }
      
      {:ok, enriched}
    rescue
      error ->
        {:error, :enrichment_error, error: error}
    end
  end
  
  defp cache_data(data, state) do
    # Implement caching logic
    # Cache processed data to avoid reprocessing
    
    cache_key = generate_cache_key(data)
    
    case Map.get(state.cache, cache_key) do
      nil ->
        # Cache the data
        cache_entry = %{
          data: data,
          timestamp: System.system_time(:second),
          ttl: @cache_ttl
        }
        
        updated_cache = Map.put(state.cache, cache_key, cache_entry)
        
        # Return updated state with cached data
        {:ok, data, %{state | cache: updated_cache}}
      
      cached ->
        # Return cached data
        {:ok, cached.data, state}
    end
  end
  
  # Helper methods
  defp update_metrics(state, input_count, output_count) do
    error_count = input_count - output_count
    
    %{state | metrics: %{
      state.metrics
      | 
      processed: state.metrics.processed + output_count,
      errors: state.metrics.errors + error_count,
      last_processed: System.system_time(:second)
    }}
  end
  
  defp generate_cache_key(data) do
    # Create a consistent cache key based on data content
    # For simplicity, we'll use a hash of the data
    data_string = data |> Map.from_struct() |> Jason.encode!()
    :crypto.hash(:sha256, data_string) |> Base.encode16()
  end
  
  defp calculate_data_quality(data) do
    # Simple data quality calculation
    # This would be more sophisticated in production
    
    required_fields = ["id", "timestamp", "source"]
    present_fields = Enum.count(required_fields, &Map.has_key?(data, &1))
    
    quality_score = present_fields / length(required_fields)
    
    case quality_score do
      1.0 -> "high"
      s when s >= 0.7 -> "medium"
      _ -> "low"
    end
  end
  
  defp normalize_value(value) when is_float(value) do
    # Normalize value to 0-1 range based on expected bounds
    # This is a placeholder - real implementation would use domain knowledge
    min_val = 0
    max_val = 100
    
    (value - min_val) / (max_val - min_val)
  rescue
    _ -> 0.0
  end
  
  defp normalize_value(_), do: 0.0
  
  defp handle_config_changes(state, changed, _removed) do
    # Handle configuration changes
    case changed do
      %{"data_processing" => new_config} ->
        updated_state = %{
          state | 
          config: Map.merge(state.config, new_config)
        }
        Logger.info("Data Processing Pipeline configuration updated")
        updated_state
      
      _ ->
        state
    end
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Data Processing Pipeline shutting down")
    :ok
  end
end