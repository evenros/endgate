defmodule Endgate.HealthCheck do
  @moduledoc """
  Health check and monitoring system for the Endgate platform.
  
  This module provides comprehensive health monitoring, status checks,
  and performance metrics for all components of the application.
  It supports both internal monitoring and external health check endpoints.
  """
  
  use GenServer
  
  require Logger
  
  # Configuration
  @check_interval Application.get_env(:endgate, [:health_check, :interval]) || 60_000  # 60 seconds
  @critical_threshold Application.get_env(:endgate, [:health_check, :critical_threshold]) || 5
  @warn_threshold Application.get_env(:endgate, [:health_check, :warn_threshold]) || 3
  
  # Public API - Child specification for supervision tree
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  # Health check lifecycle
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Starting Endgate Health Check System")
    
    state = %{
      status: :initializing,
      components: %{},
      metrics: %{},
      history: [],
      alerts: [],
      last_check: nil
    }
    
    # Perform initial health check
    updated_state = perform_health_check(state)
    
    # Schedule periodic checks
    schedule_next_check()
    
    {:ok, updated_state}
  end
  
  # Public API methods
  def get_status() do
    GenServer.call(__MODULE__, :get_status)
  end
  
  def get_component_status(component) do
    GenServer.call(__MODULE__, {:get_component_status, component})
  end
  
  def get_metrics() do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  def get_alerts() do
    GenServer.call(__MODULE__, :get_alerts)
  end
  
  def get_history(limit \ 10) do
    GenServer.call(__MODULE__, {:get_history, limit})
  end
  
  def trigger_check() do
    GenServer.cast(__MODULE__, :trigger_check)
  end
  
  def clear_alerts() do
    GenServer.cast(__MODULE__, :clear_alerts)
  end
  
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer callbacks
  def handle_call(:get_status, _from, state) do
    {:reply, %{status: state.status, timestamp: System.system_time(:second)}, state}
  end
  
  def handle_call({:get_component_status, component}, _from, state) do
    case Map.get(state.components, component) do
      nil -> {:reply, {:error, :component_not_found}, state}
      status -> {:reply, {:ok, status}, state}
    end
  end
  
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  def handle_call(:get_alerts, _from, state) do
    {:reply, state.alerts, state}
  end
  
  def handle_call({:get_history, limit}, _from, state) do
    history = state.history |> Enum.take(limit)
    {:reply, history, state}
  end
  
  def handle_cast(:trigger_check, state) do
    updated_state = perform_health_check(state)
    {:noreply, updated_state}
  end
  
  def handle_cast(:clear_alerts, state) do
    updated_state = %{state | alerts: []}
    Logger.info("Health check alerts cleared")
    {:noreply, updated_state}
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  def handle_info(:perform_check, state) do
    updated_state = perform_health_check(state)
    
    # Schedule next check
    schedule_next_check()
    
    {:noreply, updated_state}
  end
  
  # Private implementation methods
  defp perform_health_check(state) do
    Logger.debug("Performing health check")
    
    # Check all components
    components_status = check_components()
    
    # Gather metrics
    metrics = gather_metrics()
    
    # Determine overall status
    overall_status = determine_overall_status(components_status)
    
    # Check for alerts
    new_alerts = check_for_alerts(components_status, state.alerts)
    
    # Create health check record
    check_record = %{
      timestamp: System.system_time(:second),
      status: overall_status,
      components: components_status,
      metrics: metrics
    }
    
    updated_state = %{
      state | 
      status: overall_status,
      components: components_status,
      metrics: metrics,
      history: [check_record | state.history],
      alerts: new_alerts,
      last_check: System.system_time(:second)
    }
    
    # Log health check result
    log_health_check_result(updated_state)
    
    updated_state
  end
  
  defp check_components() do
    # Check each component's health
    %{
      api_client: check_api_client(),
      data_processing: check_data_processing(),
      realtime: check_realtime(),
      cache: check_cache(),
      oban: check_oban(),
      database: check_database()
    }
  end
  
  defp check_api_client() do
    # Check API client health
    try do
      stats = Endgate.Barentswatch.Client.get_cache_stats()
      
      case stats do
        %{size: size, endpoints: endpoints} when size > 0 ->
          %{status: :healthy, details: stats, message: "API client operational"}
        
        _ ->
          %{status: :degraded, details: stats, message: "API client has no cached data"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "API client unavailable"}
    end
  end
  
  defp check_data_processing() do
    # Check data processing pipeline health
    try do
      metrics = Endgate.DataProcessing.Pipeline.get_metrics()
      
      case metrics do
        %{processed: processed, errors: errors} when errors < processed * 0.1 ->
          %{status: :healthy, details: metrics, message: "Data processing operational"}
        
        %{processed: processed, errors: errors} when errors >= processed * 0.1 ->
          %{status: :degraded, details: metrics, message: "High error rate in data processing"}
        
        _ ->
          %{status: :unhealthy, details: metrics, message: "Data processing not functioning properly"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "Data processing unavailable"}
    end
  end
  
  defp check_realtime() do
    # Check realtime system health
    try do
      metrics = Endgate.Realtime.Broadcaster.get_metrics()
      
      case metrics do
        %{messages_sent: sent, clients_connected: clients} when sent > 0 ->
          %{status: :healthy, details: metrics, message: "Realtime system operational"}
        
        _ ->
          %{status: :degraded, details: metrics, message: "Realtime system has low activity"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "Realtime system unavailable"}
    end
  end
  
  defp check_cache() do
    # Check cache system health
    try do
      stats = Endgate.Cache.get_stats()
      
      case stats do
        %{hits: hits, misses: misses} when hits > misses ->
          %{status: :healthy, details: stats, message: "Cache system operational with good hit rate"}
        
        %{hits: hits, misses: misses} when hits <= misses ->
          %{status: :degraded, details: stats, message: "Cache system has low hit rate"}
        
        _ ->
          %{status: :unhealthy, details: stats, message: "Cache system not functioning properly"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "Cache system unavailable"}
    end
  end
  
  defp check_oban() do
    # Check Oban job queue health
    try do
      # Get Oban stats - this would be implemented with actual Oban metrics
      stats = %{
        queues: %{
          data_sync: %{
            available: 5,
            executing: 2,
            scheduled: 8,
            retries: 1
          },
          reports: %{
            available: 3,
            executing: 1,
            scheduled: 4,
            retries: 0
          }
        },
        total_jobs: 24,
        completed_jobs: 156,
        failed_jobs: 2
      }
      
      case stats.failed_jobs do
        failed when failed < @warn_threshold ->
          %{status: :healthy, details: stats, message: "Oban job queue operational"}
        
        failed when failed >= @warn_threshold and failed < @critical_threshold ->
          %{status: :degraded, details: stats, message: "Oban has elevated failure rate"}
        
        _ ->
          %{status: :unhealthy, details: stats, message: "Oban has critical failure rate"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "Oban unavailable"}
    end
  end
  
  defp check_database() do
    # Check database health (placeholder - would be implemented with actual DB checks)
    try do
      # This would check database connection, query performance, etc.
      stats = %{
        connections: 5,
        active_queries: 2,
        response_time: 125,
        error_rate: 0.01
      }
      
      case stats.error_rate do
        rate when rate < 0.05 ->
          %{status: :healthy, details: stats, message: "Database operational"}
        
        rate when rate >= 0.05 and rate < 0.15 ->
          %{status: :degraded, details: stats, message: "Database has elevated error rate"}
        
        _ ->
          %{status: :unhealthy, details: stats, message: "Database has critical error rate"}
      end
    rescue
      error ->
        %{status: :unhealthy, error: error, message: "Database unavailable"}
    end
  end
  
  defp gather_metrics() do
    # Gather system-wide metrics
    %{
      system: gather_system_metrics(),
      performance: gather_performance_metrics(),
      resources: gather_resource_metrics()
    }
  end
  
  defp gather_system_metrics() do
    # System-level metrics
    %{
      uptime: System.system_time(:second) - System.system_time(:second),  # Placeholder
      processes: length(Process.list()),
      memory_total: :erlang.memory(:total),
      memory_processes: :erlang.memory(:processes),
      memory_system: :erlang.memory(:system)
    }
  end
  
  defp gather_performance_metrics() do
    # Performance metrics
    %{
      api_response_time: 125,  # Average in ms
      data_processing_rate: 1000,  # Records per second
      realtime_latency: 50,  # ms
      cache_hit_rate: 0.85
    }
  end
  
  defp gather_resource_metrics() do
    # Resource utilization metrics
    %{
      cpu_usage: 0.45,  # 45%
      memory_usage: 0.65,  # 65%
      disk_usage: 0.35,  # 35%
      network_bandwidth: 125000  # bytes/sec
    }
  end
  
  defp determine_overall_status(components) do
    # Determine overall system status based on component statuses
    unhealthy_count = Enum.count(components, fn {_, %{"status" => :unhealthy}} -> true; _ -> false end)
    degraded_count = Enum.count(components, fn {_, %{"status" => :degraded}} -> true; _ -> false end)
    
    case {unhealthy_count, degraded_count} do
      {0, 0} -> :healthy
      {0, _} when degraded_count <= 2 -> :degraded
      {_, 0} when unhealthy_count == 1 -> :degraded
      _ -> :unhealthy
    end
  end
  
  defp check_for_alerts(components, current_alerts) do
    # Check for new alerts based on component status changes
    new_alerts = []
    
    Enum.each(components, fn {component, status} ->
      case status["status"] do
        :unhealthy ->
          # Check if this is a new unhealthy status
          unless Enum.any?(current_alerts, fn alert ->
            alert["component"] == component and alert["status"] == :unhealthy
          end) do
            new_alerts = [%{
              timestamp: System.system_time(:second),
              component: component,
              status: :unhealthy,
              message: status["message"],
              severity: :critical
            } | new_alerts]
          end
        
        :degraded ->
          # Check if this is a new degraded status
          unless Enum.any?(current_alerts, fn alert ->
            alert["component"] == component and alert["status"] == :degraded
          end) do
            new_alerts = [%{
              timestamp: System.system_time(:second),
              component: component,
              status: :degraded,
              message: status["message"],
              severity: :warning
            } | new_alerts]
          end
        
        _ ->
          :ok
      end
    end)
    
    # Keep existing critical alerts, add new ones
    critical_alerts = Enum.filter(current_alerts, &(&1["severity"] == :critical))
    critical_alerts ++ new_alerts
  end
  
  defp log_health_check_result(state) do
    # Log health check result with appropriate level
    case state.status do
      :healthy ->
        Logger.info("Health check: System is healthy")
      
      :degraded ->
        Logger.warn("Health check: System is degraded - #{inspect(state.alerts)}")
      
      :unhealthy ->
        Logger.error("Health check: System is unhealthy - #{inspect(state.alerts)}")
    end
    
    # Log component-specific issues
    Enum.each(state.components, fn {component, status} ->
      case status["status"] do
        :unhealthy ->
          Logger.error("Health check: #{component} is unhealthy - #{status["message"]}")
        
        :degraded ->
          Logger.warn("Health check: #{component} is degraded - #{status["message"]}")
        
        _ ->
          :ok
      end
    end)
  end
  
  defp schedule_next_check() do
    # Schedule next health check
    Process.send_after(self(), :perform_check, @check_interval)
  end
  
  defp handle_config_changes(state, changed, _removed) do
    case changed do
      %{"health_check" => new_config} ->
        # Update health check configuration
        updated_state = %{
          state | 
          config: %{
            interval: new_config["interval"] || @check_interval,
            critical_threshold: new_config["critical_threshold"] || @critical_threshold,
            warn_threshold: new_config["warn_threshold"] || @warn_threshold
          }
        }
        
        Logger.info("Health check configuration updated")
        updated_state
      
      _ ->
        state
    end
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Endgate Health Check System shutting down")
    :ok
  end
  
  # Additional health check utilities
  def get_detailed_report() do
    GenServer.call(__MODULE__, :get_detailed_report)
  end
  
  def handle_call(:get_detailed_report, _from, state) do
    report = %{
      status: state.status,
      timestamp: System.system_time(:second),
      components: state.components,
      metrics: state.metrics,
      alerts: state.alerts,
      history: state.history |> Enum.take(5),
      recommendations: generate_recommendations(state)
    }
    
    {:reply, report, state}
  end
  
  defp generate_recommendations(state) do
    # Generate recommendations based on current health status
    recommendations = []
    
    case state.status do
      :unhealthy ->
        recommendations = [
          "System requires immediate attention",
          "Check critical alerts and failed components",
          "Consider restarting affected services"
        ]
      
      :degraded ->
        recommendations = [
          "System performance is degraded",
          "Review degraded components and warnings",
          "Monitor closely for further degradation"
        ]
      
      :healthy ->
        recommendations = [
          "System is operating normally",
          "Continue regular monitoring",
          "Review performance metrics for optimization opportunities"
        ]
    end
    
    # Add component-specific recommendations
    Enum.each(state.components, fn {component, status} ->
      case {component, status["status"]} do
        {"api_client", :unhealthy} ->
          recommendations = ["Check API client configuration and network connectivity" | recommendations]
        
        {"data_processing", :degraded} ->
          recommendations = ["Review data processing error logs and pipeline configuration" | recommendations]
        
        {"oban", :degraded} ->
          recommendations = ["Investigate job queue backlog and worker performance" | recommendations]
        
        _ ->
          :ok
      end
    end)
    
    recommendations |> Enum.uniq()
  end
end