defmodule Endgate.Workers.ReportGenerator do
  @moduledoc """
  Background worker for report generation.
  
  This worker handles the generation of various reports including
  data summaries, analytics reports, and system status reports.
  """
  
  use Oban.Worker, 
    queue: :reports,
    max_attempts: 2,
    backoff: [:linear, :seconds, 10]
  
  require Logger
  
  @impl true
  def perform(%Oban.Job{args: %{"report_type" => report_type, "params" => params}}) do
    Logger.info("Generating report: #{report_type}")
    
    case generate_report(report_type, params) do
      {:ok, report} ->
        Logger.info("Report generated successfully: #{report_type}")
        
        # Store the report
        store_report(report_type, report, params)
        
        {:ok, %{report_type: report_type, status: "completed"}}
      
      {:error, reason} ->
        Logger.error("Report generation failed: #{reason}")
        {:error, reason}
    end
  end
  
  # Private implementation
  defp generate_report("data_summary", params) do
    # Generate data summary report
    from_date = params["from_date"] || DateTime.utc_now() |> DateTime.to_date() |> DateTime.from_date!() |> DateTime.add(-7, :day)
    to_date = params["to_date"] || DateTime.utc_now()
    
    # Get data from various sources
    ais_data = get_ais_summary_data(from_date, to_date)
    met_data = get_met_summary_data(from_date, to_date)
    
    # Generate report
    report = %{
      type: "data_summary",
      period: %{
        from: from_date,
        to: to_date
      },
      generated_at: System.system_time(:second),
      sections: %{
        ais: ais_data,
        meteorological: met_data,
        system: get_system_summary()
      }
    }
    
    {:ok, report}
  end
  
  defp generate_report("analytics", params) do
    # Generate analytics report
    data_type = params["data_type"] || "vessel_movements"
    period = params["period"] || "weekly"
    
    # Generate analytics based on data type
    analytics = case data_type do
      "vessel_movements" -> generate_vessel_analytics(period)
      "weather_patterns" -> generate_weather_analytics(period)
      "system_performance" -> generate_system_analytics(period)
      _ -> %{error: :unsupported_data_type}
    end
    
    case analytics do
      %{error: _} -> {:error, :unsupported_analytics_type}
      _ -> {:ok, %{type: "analytics", data_type: data_type, period: period, analytics: analytics}}
    end
  end
  
  defp generate_report("system_status", _params) do
    # Generate system status report
    metrics = %{
      api_client: Endgate.Barentswatch.Client.get_cache_stats(),
      data_processing: Endgate.DataProcessing.Pipeline.get_metrics(),
      realtime: Endgate.Realtime.Broadcaster.get_metrics(),
      oban: get_oban_metrics()
    }
    
    report = %{
      type: "system_status",
      timestamp: System.system_time(:second),
      metrics: metrics,
      status: assess_system_status(metrics)
    }
    
    {:ok, report}
  end
  
  defp generate_report(report_type, _params) do
    {:error, :unsupported_report_type, type: report_type}
  end
  
  defp get_ais_summary_data(from_date, to_date) do
    # This would fetch actual data in a real implementation
    # For now, we'll return mock data
    %{
      total_vessels: 150,
      active_vessels: 75,
      data_points: 1250,
      average_speed: 12.5,
      most_common_vessel_type: "Cargo"
    }
  end
  
  defp get_met_summary_data(from_date, to_date) do
    %{
      temperature_range: %{
        min: 5.2,
        max: 18.7,
        average: 12.3
      },
      wind_speed_range: %{
        min: 2.1,
        max: 25.8,
        average: 12.4
      },
      weather_events: 3
    }
  end
  
  defp get_system_summary() do
    %{
      uptime: "7 days, 3 hours, 22 minutes",
      memory_usage: "456MB",
      cpu_usage: "12.4%",
      active_connections: 15
    }
  end
  
  defp generate_vessel_analytics(period) do
    case period do
      "daily" ->
        %{
          period: "daily",
          total_movements: 450,
          average_distance: 125.4,
          busiest_area: "Oslo Fjord",
          vessel_types: %{"Cargo" => 45, "Tanker" => 25, "Passenger" => 15}
        }
      
      "weekly" ->
        %{
          period: "weekly",
          total_movements: 3150,
          average_distance: 878.2,
          busiest_area: "North Sea",
          vessel_types: %{"Cargo" => 315, "Tanker" => 175, "Passenger" => 105}
        }
      
      "monthly" ->
        %{
          period: "monthly",
          total_movements: 13500,
          average_distance: 3805.6,
          busiest_area: "Barents Sea",
          vessel_types: %{"Cargo" => 1350, "Tanker" => 750, "Passenger" => 450}
        }
    end
  end
  
  defp generate_weather_analytics(period) do
    case period do
      "daily" ->
        %{
          period: "daily",
          temperature_trend: "stable",
          wind_trend: "increasing",
          extreme_events: 1
        }
      
      "weekly" ->
        %{
          period: "weekly",
          temperature_trend: "rising",
          wind_trend: "variable",
          extreme_events: 4
        }
      
      "monthly" ->
        %{
          period: "monthly",
          temperature_trend: "seasonal",
          wind_trend: "cyclical",
          extreme_events: 12
        }
    end
  end
  
  defp generate_system_analytics(period) do
    case period do
      "daily" ->
        %{
          period: "daily",
          api_success_rate: 98.7,
          processing_time_avg: 125,
          memory_usage_avg: 420
        }
      
      "weekly" ->
        %{
          period: "weekly",
          api_success_rate: 97.2,
          processing_time_avg: 142,
          memory_usage_avg: 456
        }
      
      "monthly" ->
        %{
          period: "monthly",
          api_success_rate: 96.8,
          processing_time_avg: 158,
          memory_usage_avg: 489
        }
    end
  end
  
  defp get_oban_metrics() do
    # Get Oban job queue metrics
    %{
      queues: %{
        "data_sync" => %{
          available: 5,
          executing: 2,
          scheduled: 8,
          retries: 1
        },
        "reports" => %{
          available: 3,
          executing: 1,
          scheduled: 4,
          retries: 0
        }
      },
      total_jobs: 24,
      completed_jobs: 156
    }
  end
  
  defp assess_system_status(metrics) do
    # Simple system status assessment
    api_success_rate = Map.get(metrics, [:api_client, :request_count]) || 0
    processing_errors = Map.get(metrics, [:data_processing, :errors]) || 0
    
    if processing_errors > 100 do
      "degraded"
    else
      "healthy"
    end
  end
  
  defp store_report(report_type, report, params) do
    # In a real implementation, this would store the report
    # For now, we'll just log it and broadcast it
    
    # Convert to JSON for storage
    report_json = Jason.encode!(report)
    
    # Broadcast the report
    topic = "reports:#{report_type}"
    Endgate.Realtime.Broadcaster.broadcast(topic, report)
    
    # Log storage
    Logger.info("Report stored: #{report_type}")
    
    :ok
  end
end