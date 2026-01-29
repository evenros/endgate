defmodule Endgate.Workers.DataSync do
  @moduledoc """
  Background worker for data synchronization.
  
  This worker handles periodic data synchronization from the Barentswatch API
  and other data sources. It uses Oban for job scheduling and retry logic.
  """
  
  use Oban.Worker, 
    queue: :data_sync,
    max_attempts: 3,
    backoff: [:exponential, :seconds, 5]
  
  require Logger
  
  @impl true
  def perform(%Oban.Job{args: %{"source" => source, "params" => params}}) do
    Logger.info("Starting data sync for source: #{source}")
    
    case sync_data(source, params) do
      {:ok, result} ->
        Logger.info("Data sync completed successfully for #{source}")
        {:ok, result}
      
      {:error, reason} ->
        Logger.error("Data sync failed for #{source}: #{reason}")
        {:error, reason}
    end
  end
  
  # Private implementation
  defp sync_data("barentswatch_ais", params) do
    # Sync AIS data from Barentswatch
    endpoint = "/ais/vessels"
    
    case Endgate.Barentswatch.Client.fetch(endpoint, params) do
      {:ok, data} ->
        # Process data through pipeline
        processed_data = process_ais_data(data)
        
        # Store or broadcast the data
        broadcast_processed_data("ais:vessels", processed_data)
        
        {:ok, %{source: "barentswatch_ais", records: length(processed_data)}}
      
      {:error, reason, details} ->
        {:error, :api_error, reason: reason, details: details}
    end
  end
  
  defp sync_data("barentswatch_met", params) do
    # Sync meteorological data from Barentswatch
    endpoint = "/met/forecast"
    
    case Endgate.Barentswatch.Client.fetch(endpoint, params) do
      {:ok, data} ->
        # Process data through pipeline
        processed_data = process_met_data(data)
        
        # Store or broadcast the data
        broadcast_processed_data("met:forecast", processed_data)
        
        {:ok, %{source: "barentswatch_met", records: length(processed_data)}}
      
      {:error, reason, details} ->
        {:error, :api_error, reason: reason, details: details}
    end
  end
  
  defp sync_data(source, _params) do
    {:error, :unsupported_source, source: source}
  end
  
  defp process_ais_data(data) do
    # Process AIS data through the data processing pipeline
    # This would include validation, transformation, and enrichment
    
    case data do
      %{"vessels" => vessels} ->
        vessels
        |> Enum.map(&process_single_vessel(&1))
        |> Enum.filter(& &1 != nil)
      
      _ ->
        []
    end
  end
  
  defp process_single_vessel(vessel) do
    # Add processing metadata and validate
    try do
      validated = validate_vessel_data(vessel)
      
      case validated do
        {:ok, valid_vessel} ->
          # Transform and enrich
          transformed = transform_vessel_data(valid_vessel)
          enriched = enrich_vessel_data(transformed)
          
          # Process through main pipeline
          Endgate.DataProcessing.Pipeline.process_data(enriched)
          enriched
        
        {:error, _} ->
          nil
      end
    rescue
      _ -> nil
    end
  end
  
  defp validate_vessel_data(vessel) do
    # Validate required vessel fields
    required_fields = ["mmsi", "name", "position", "timestamp"]
    
    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(vessel, field)
    end)
    
    if missing == [] do
      {:ok, vessel}
    else
      {:error, :missing_fields, missing: missing}
    end
  end
  
  defp transform_vessel_data(vessel) do
    # Transform vessel data to standard format
    %{
      vessel
      | 
      # Standardize position format
      position: standardize_position(vessel["position"]),
      
      # Convert timestamp
      timestamp: to_string(vessel["timestamp"]),
      
      # Add processing metadata
      processed_at: System.system_time(:second),
      source: "barentswatch_ais",
      data_type: "vessel"
    }
  end
  
  defp enrich_vessel_data(vessel) do
    # Add derived fields to vessel data
    %{
      vessel
      | 
      # Calculate speed if position history available
      speed: calculate_speed(vessel),
      
      # Add data quality indicators
      data_quality: assess_vessel_quality(vessel),
      
      # Add processing stage
      processing_stage: "enriched"
    }
  end
  
  defp process_met_data(data) do
    # Process meteorological data
    case data do
      %{"forecast" => forecast} ->
        forecast
        |> Enum.map(&process_forecast_point(&1))
        |> Enum.filter(& &1 != nil)
      
      _ ->
        []
    end
  end
  
  defp process_forecast_point(point) do
    try do
      validated = validate_forecast_data(point)
      
      case validated do
        {:ok, valid_point} ->
          transformed = transform_forecast_data(valid_point)
          enriched = enrich_forecast_data(transformed)
          
          Endgate.DataProcessing.Pipeline.process_data(enriched)
          enriched
        
        {:error, _} ->
          nil
      end
    rescue
      _ -> nil
    end
  end
  
  defp validate_forecast_data(point) do
    required_fields = ["location", "time", "temperature", "wind"]
    
    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(point, field)
    end)
    
    if missing == [] do
      {:ok, point}
    else
      {:error, :missing_fields, missing: missing}
    end
  end
  
  defp transform_forecast_data(point) do
    %{
      point
      | 
      # Standardize location format
      location: standardize_location(point["location"]),
      
      # Convert timestamp
      time: to_string(point["time"]),
      
      # Add processing metadata
      processed_at: System.system_time(:second),
      source: "barentswatch_met",
      data_type: "forecast"
    }
  end
  
  defp enrich_forecast_data(point) do
    %{
      point
      | 
      # Add derived weather indicators
      weather_index: calculate_weather_index(point),
      
      # Add data quality
      data_quality: assess_forecast_quality(point),
      
      # Add processing stage
      processing_stage: "enriched"
    }
  end
  
  defp broadcast_processed_data(topic, data) do
    # Broadcast processed data through realtime system
    case data do
      [head | _] when is_list(data) ->
        # Broadcast each item individually
        Enum.each(data, fn item ->
          Endgate.Realtime.Broadcaster.broadcast(topic, item)
        end)
      
      _ ->
        Endgate.Realtime.Broadcaster.broadcast(topic, data)
    end
  end
  
  # Helper functions
  defp standardize_position(position) when is_map(position) do
    %{
      "lat" => position["latitude"],
      "lon" => position["longitude"]
    }
  end
  
  defp standardize_position(position) when is_list(position) and length(position) >= 2 do
    %{"lat" => hd(position), "lon" => List.last(position)}
  end
  
  defp standardize_position(_), do: %{"lat" => 0.0, "lon" => 0.0}
  
  defp standardize_location(location) do
    case location do
      %{"lat" => lat, "lon" => lon} ->
        %{latitude: lat, longitude: lon}
      
      %{:lat => lat, :lon => lon} ->
        %{latitude: lat, longitude: lon}
      
      _ ->
        %{latitude: 0.0, longitude: 0.0}
    end
  end
  
  defp calculate_speed(vessel) do
    # Placeholder for speed calculation
    # Would use position history in real implementation
    0.0
  end
  
  defp assess_vessel_quality(vessel) do
    # Simple quality assessment
    required = ["mmsi", "name", "position", "timestamp"]
    present = Enum.count(required, &Map.has_key?(vessel, &1))
    
    case present / length(required) do
      1.0 -> "high"
      s when s >= 0.7 -> "medium"
      _ -> "low"
    end
  end
  
  defp calculate_weather_index(point) do
    # Simple weather index calculation
    temp = point["temperature"] || 0
    wind = Map.get(point["wind"], "speed", 0)
    
    # Simple formula - would be more sophisticated in production
    (temp * 0.7) - (wind * 0.3)
  end
  
  defp assess_forecast_quality(point) do
    required = ["location", "time", "temperature", "wind"]
    present = Enum.count(required, &Map.has_key?(point, &1))
    
    case present / length(required) do
      1.0 -> "high"
      s when s >= 0.7 -> "medium"
      _ -> "low"
    end
  end
end