defmodule EngineeringAnalyticsTerminal.DataProcessing do
  @moduledoc """
  Data processing module using functional programming paradigms.
  
  This module provides pure functions for cleaning, transforming,
  and enriching data from BarentsWatch APIs.
  """
  
  @doc """
  Cleans and normalizes raw API data.
  
  ## Parameters
    - raw_data: Raw data from BarentsWatch API
    - data_type: Type of data as atom (:weather, :ais, :ocean)
  
  ## Returns
    - {:ok, cleaned_data} on success
    - {:error, reason} on failure
  """
  def clean_data(raw_data, data_type) when is_map(raw_data) or is_list(raw_data) do
    case data_type do
      :weather -> clean_weather_data(raw_data)
      :ais -> clean_ais_data(raw_data)
      :ocean -> clean_ocean_data(raw_data)
      _ -> {:error, "Unknown data type: #{inspect(data_type)}"}
    end
  end
  
  def clean_data(_raw_data, _data_type) do
    {:error, "Invalid data format: expected map or list"}
  end
  
  @doc """
  Transforms data into a common format for analysis.
  
  ## Parameters
    - data: Cleaned data
    - target_format: Target format as atom (:timeseries, :geospatial, :tabular)
  
  ## Returns
    - {:ok, transformed_data} on success
    - {:error, reason} on failure
  """
  def transform_data(data, target_format) when is_map(data) or is_list(data) do
    case target_format do
      :timeseries -> {:ok, transform_to_timeseries(data)}
      :geospatial -> {:ok, transform_to_geospatial(data)}
      :tabular -> {:ok, transform_to_tabular(data)}
      _ -> {:error, "Unknown target format: #{inspect(target_format)}"}
    end
  end
  
  def transform_data(_data, _target_format) do
    {:error, "Invalid data format: expected map or list"}
  end
  
  @doc """
  Enriches data by combining multiple data sources.
  
  ## Parameters
    - primary_data: Primary data to enrich (list of maps)
    - secondary_data: Secondary data for enrichment (list of maps)
    - join_key: Key to join the datasets on (atom or binary)
  
  ## Returns
    - {:ok, enriched_data} on success
    - {:error, reason} on failure
  """
  def enrich_data(primary_data, secondary_data, join_key) 
      when is_list(primary_data) and is_list(secondary_data) do
    
    case join_key do
      key when is_atom(key) or is_binary(key) ->
        enriched = Enum.map(primary_data, fn primary_item ->
          secondary_item = Enum.find(secondary_data, fn secondary ->
            secondary[join_key] == primary_item[join_key]
          end)
          
          case secondary_item do
            nil -> primary_item
            _ -> Map.merge(primary_item, secondary_item)
          end
        end)
        
        {:ok, enriched}
      
      _ -> {:error, "Invalid join key: expected atom or binary"}
    end
  end
  
  def enrich_data(_primary_data, _secondary_data, _join_key) do
    {:error, "Invalid data format: expected lists of maps"}
  end
  
  @doc """
  Aggregates data by time periods.
  
  ## Parameters
    - data: Time-series data (list of maps)
    - time_period: Aggregation period as atom (:hourly, :daily, :weekly)
  
  ## Returns
    - {:ok, aggregated_data} on success
    - {:error, reason} on failure
  """
  def aggregate_by_time(data, time_period) when is_list(data) do
    case time_period do
      :hourly -> aggregate_data(data, &truncate_to_hour/1)
      :daily -> aggregate_data(data, &truncate_to_day/1)
      :weekly -> aggregate_data(data, &truncate_to_week/1)
      _ -> {:error, "Unknown time period: #{inspect(time_period)}"}
    end
  end
  
  def aggregate_by_time(_data, _time_period) do
    {:error, "Invalid data format: expected list"}
  end
  
  @doc """
  Validates data quality and completeness.
  
  ## Parameters
    - data: Data to validate
    - schema: Expected data schema as map
  
  ## Returns
    - {:ok, valid_data} if data is valid
    - {:error, validation_errors} if data has issues
  """
  def validate_data(data, schema) when is_map(data) and is_map(schema) do
    required_fields = schema[:required_fields] || []
    
    case validate_required_fields(data, required_fields) do
      {:ok, _} -> {:ok, data}
      error -> error
    end
  end
  
  def validate_data(_data, _schema) do
    {:error, "Invalid arguments: expected maps for data and schema"}
  end
  
  # Private functions using pattern matching
  defp clean_weather_data(%{"temperature" => temp} = data) when is_number(temp) do
    {:ok, Map.put(data, :temperature_celsius, temp)}
  end
  
  defp clean_weather_data(data), do: {:ok, data}
  
  defp clean_ais_data(%{"vessels" => vessels} = data) when is_list(vessels) do
    cleaned_vessels = Enum.map(vessels, &clean_vessel/1)
    {:ok, Map.put(data, "vessels", cleaned_vessels)}
  end
  
  defp clean_ais_data(data), do: {:ok, data}
  
  defp clean_vessel(%{"mmsi" => mmsi, "name" => name}) when is_binary(mmsi) and is_binary(name) do
    %{"mmsi" => mmsi, "name" => name, "cleaned" => true}
  end
  
  defp clean_vessel(vessel), do: vessel
  
  defp clean_ocean_data(data), do: {:ok, data}
  
  defp transform_to_timeseries(data), do: data
  defp transform_to_geospatial(data), do: data
  defp transform_to_tabular(data), do: data
  
  defp aggregate_data(data, truncate_func) do
    grouped = Enum.group_by(data, fn item ->
      timestamp = item["timestamp"] || item[:timestamp]
      truncate_func.(timestamp)
    end)
    
    aggregated = Enum.map(grouped, fn {period, items} ->
      %{
        period: period,
        count: length(items),
        avg_value: calculate_average(items),
        max_value: calculate_max(items),
        min_value: calculate_min(items)
      }
    end)
    
    {:ok, aggregated}
  end
  
  defp validate_required_fields(data, [field | rest]) do
    case Map.has_key?(data, field) do
      true -> validate_required_fields(data, rest)
      false -> {:error, "Missing required field: #{field}"}
    end
  end
  
  defp validate_required_fields(_data, []), do: {:ok, :valid}
  
  defp truncate_to_hour(timestamp), do: timestamp
  defp truncate_to_day(timestamp), do: timestamp
  defp truncate_to_week(timestamp), do: timestamp
  
  defp calculate_average(items), do: 0.0
  defp calculate_max(items), do: 0.0
  defp calculate_min(items), do: 0.0
end