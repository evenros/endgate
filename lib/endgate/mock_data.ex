defmodule Endgate.MockData do
  @moduledoc """
  Mock data system for development and testing.
  
  This module provides realistic mock data that simulates the Barentswatch API
  and other data sources. It's used during development when the actual API
  is not available or to simulate various scenarios.
  """
  
  require Logger
  
  # Configuration
  @mock_mode Application.get_env(:endgate, [:api_client, :barentswatch, :mock_mode]) || false
  @mock_data_dir Application.get_env(:endgate, :mock_data_dir) || "priv/mock_data"
  
  # Public API
  def generate_mock_response(endpoint, params \ %{}) do
    if @mock_mode do
      Logger.debug("Generating mock response for: #{endpoint}")
      generate_response_for_endpoint(endpoint, params)
    else
      {:error, :mock_mode_disabled}
    end
  end
  
  def enable_mock_mode() do
    Application.put_env(:endgate, [:api_client, :barentswatch, :mock_mode], true)
    Logger.info("Mock data mode enabled")
    :ok
  end
  
  def disable_mock_mode() do
    Application.put_env(:endgate, [:api_client, :barentswatch, :mock_mode], false)
    Logger.info("Mock data mode disabled")
    :ok
  end
  
  def is_mock_mode_enabled? do
    @mock_mode
  end
  
  def generate_ais_vessels(params \ %{}) do
    # Generate mock AIS vessel data
    count = params["count"] || 10
    area = params["area"] || "norway"
    
    vessels = Enum.map(1..count, &generate_mock_vessel(&1, area))
    
    %{
      "vessels" => vessels,
      "metadata" => %{
        "source" => "barentswatch_ais_mock",
        "generated_at" => System.system_time(:second),
        "count" => length(vessels),
        "area" => area
      }
    }
  end
  
  def generate_met_forecast(params \ %{}) do
    # Generate mock meteorological forecast data
    location = params["location"] || "oslo"
    days = params["days"] || 5
    
    forecast = Enum.map(1..days, &generate_mock_forecast_point(&1, location))
    
    %{
      "forecast" => forecast,
      "metadata" => %{
        "source" => "barentswatch_met_mock",
        "generated_at" => System.system_time(:second),
        "location" => location,
        "days" => days
      }
    }
  end
  
  def generate_system_metrics() do
    # Generate mock system metrics
    %{
      "api_client" => %{
        "request_count" => Enum.random(100..1000),
        "cache_hits" => Enum.random(50..500),
        "errors" => Enum.random(0..10)
      },
      "data_processing" => %{
        "processed" => Enum.random(1000..10000),
        "errors" => Enum.random(0..50),
        "cache_size" => Enum.random(10..100)
      },
      "realtime" => %{
        "messages_sent" => Enum.random(500..5000),
        "clients_connected" => Enum.random(0..50),
        "active_topics" => Enum.random(1..10)
      }
    }
  end
  
  # Private implementation
  defp generate_response_for_endpoint(endpoint, params) do
    case endpoint do
      "/ais/vessels" ->
        {:ok, generate_ais_vessels(params)}
      
      "/met/forecast" ->
        {:ok, generate_met_forecast(params)}
      
      "/system/metrics" ->
        {:ok, generate_system_metrics()}
      
      _ ->
        {:error, :unknown_endpoint, endpoint: endpoint}
    end
  end
  
  defp generate_mock_vessel(id, area) do
    # Generate a realistic mock vessel
    vessel_types = ["Cargo", "Tanker", "Passenger", "Fishing", "Military", "Pleasure"]
    statuses = ["Under way using engine", "At anchor", "Moored", "Restricted maneuverability"]
    
    base_position = get_area_position(area)
    
    %{
      "mmsi" => 257000000 + id,
      "name" => "MV-MOCK-#{String.pad_leading(integer_to_string(id), 4, "0")}",
      "vessel_type" => Enum.random(vessel_types),
      "status" => Enum.random(statuses),
      "position" => %{
        "latitude" => base_position["lat"] + (Enum.random(-0.1..0.1)),
        "longitude" => base_position["lon"] + (Enum.random(-0.1..0.1))
      },
      "speed" => Enum.random(0.0..25.0),
      "course" => Enum.random(0..359),
      "timestamp" => generate_timestamp(),
      "destination" => generate_destination(area),
      "eta" => generate_eta(),
      "draught" => Enum.random(5.0..15.0),
      "length" => Enum.random(50..300),
      "width" => Enum.random(10..50)
    }
  end
  
  defp generate_mock_forecast_point(day, location) do
    # Generate a realistic mock forecast point
    base_temp = get_base_temperature(location)
    
    %{
      "time" => generate_forecast_time(day),
      "location" => get_location_coordinates(location),
      "temperature" => base_temp + Enum.random(-5.0..5.0),
      "wind" => %{
        "speed" => Enum.random(0.0..25.0),
        "direction" => Enum.random(0..359),
        "gusts" => Enum.random(0.0..35.0)
      },
      "precipitation" => %{
        "type" => Enum.random(["rain", "snow", "none"]),
        "intensity" => Enum.random(0.0..10.0)
      },
      "pressure" => Enum.random(950..1050),
      "humidity" => Enum.random(30..100),
      "visibility" => Enum.random(0.1..50.0),
      "weather_code" => Enum.random(0..49)
    }
  end
  
  # Helper functions for data generation
  defp get_area_position(area) do
    case area do
      "norway" -> %{"lat" => 60.4720, "lon" => 8.4689}
      "oslo" -> %{"lat" => 59.9139, "lon" => 10.7522}
      "bergen" -> %{"lat" => 60.3913, "lon" => 5.3221}
      "trondheim" -> %{"lat" => 63.4305, "lon" => 10.3951}
      "barents_sea" -> %{"lat" => 73.0, "lon" => 30.0}
      "north_sea" -> %{"lat" => 57.0, "lon" => 2.0}
      _ -> %{"lat" => 62.0, "lon" => 10.0}
    end
  end
  
  defp get_base_temperature(location) do
    case location do
      "barents_sea" -> -2.5
      "north_sea" -> 8.7
      "trondheim" -> 6.3
      "bergen" -> 9.1
      "oslo" -> 7.8
      _ -> 5.0
    end
  end
  
  defp get_location_coordinates(location) do
    case location do
      "oslo" -> %{"lat" => 59.9139, "lon" => 10.7522}
      "bergen" -> %{"lat" => 60.3913, "lon" => 5.3221}
      "trondheim" -> %{"lat" => 63.4305, "lon" => 10.3951}
      "barents_sea" -> %{"lat" => 73.0, "lon" => 30.0}
      "north_sea" -> %{"lat" => 57.0, "lon" => 2.0}
      _ -> %{"lat" => 60.0, "lon" => 10.0}
    end
  end
  
  defp generate_timestamp() do
    # Generate a timestamp within the last 24 hours
    now = System.system_time(:second)
    offset = Enum.random(0..86400)  # 24 hours in seconds
    now - offset
  end
  
  defp generate_forecast_time(day) do
    # Generate a forecast time for the given day
    base_time = DateTime.utc_now()
    days_ahead = day - 1
    
    DateTime.add(base_time, days_ahead, :day)
    |> DateTime.to_iso8601()
  end
  
  defp generate_destination(area) do
    destinations = [
      "Oslo", "Bergen", "Trondheim", "Stavanger", "Kristiansand",
      "Tromsø", "Bodø", "Ålesund", "Haugesund", "Fredrikstad"
    ]
    
    Enum.random(destinations)
  end
  
  defp generate_eta() do
    # Generate ETA within the next 7 days
    now = DateTime.utc_now()
    hours_ahead = Enum.random(1..168)  # 7 days in hours
    
    DateTime.add(now, hours_ahead, :hour)
    |> DateTime.to_iso8601()
  end
  
  # File-based mock data loading (for more complex scenarios)
  def load_mock_data_from_file(filename) do
    if File.exists?("#{@mock_data_dir}/#{filename}.json") do
      case File.read("#{@mock_data_dir}/#{filename}.json") do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, :json_parse_error, reason: reason}
          end
        
        {:error, reason} ->
          {:error, :file_read_error, reason: reason}
      end
    else
      {:error, :file_not_found, filename: filename}
    end
  end
  
  def save_mock_data_to_file(filename, data) do
    # Ensure directory exists
    File.mkdir_p!(@mock_data_dir)
    
    case Jason.encode(data) do
      {:ok, json} ->
        case File.write("#{@mock_data_dir}/#{filename}.json", json) do
          :ok -> :ok
          {:error, reason} -> {:error, :file_write_error, reason: reason}
        end
      
      {:error, reason} ->
        {:error, :json_encode_error, reason: reason}
    end
  end
  
  # Scenario simulation
  def simulate_api_error(error_type) do
    case error_type do
      :connection_error ->
        {:error, :connection_error, "Simulated connection failure"}
      
      :authentication_error ->
        {:error, :authentication_error, "Simulated authentication failure"}
      
      :rate_limit_error ->
        {:error, :rate_limit_error, "Simulated rate limit exceeded"}
      
      :timeout ->
        {:error, :timeout, "Simulated request timeout"}
      
      _ ->
        {:error, :unknown_error, "Simulated unknown error"}
    end
  end
  
  def simulate_data_quality(quality) do
    case quality do
      :high ->
        generate_ais_vessels(%{"count" => 10, "complete_data" => true})
      
      :medium ->
        # Generate data with some missing fields
        data = generate_ais_vessels(%{"count" => 10})
        %{"vessels" => remove_random_fields(data["vessels"], 0.2)}
      
      :low ->
        # Generate data with many missing fields
        data = generate_ais_vessels(%{"count" => 10})
        %{"vessels" => remove_random_fields(data["vessels"], 0.5)}
    end
  end
  
  defp remove_random_fields(vessels, probability) do
    Enum.map(vessels, fn vessel ->
      fields = Map.keys(vessel)
      fields_to_remove = Enum.filter(fields, fn _ -> Enum.random() < probability end)
      Map.drop(vessel, fields_to_remove)
    end)
  end
end