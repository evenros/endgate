defmodule Endgate.Barentswatch.Client do
  @moduledoc """
  Main client for Barentswatch API integration.
  
  This GenServer handles all communication with the Barentswatch API,
  including authentication, connection pooling, rate limiting, and error handling.
  """
  
  use GenServer
  use Tesla
  
  require Logger
  
  # Client configuration
  @base_url Application.get_env(:endgate, [:api_client, :barentswatch, :base_url]) || "https://api.barentswatch.no"
  @timeout Application.get_env(:endgate, [:api_client, :barentswatch, :timeout]) || 30_000
  @max_retries Application.get_env(:endgate, [:api_client, :barentswatch, :max_retries]) || 3
  @retry_delay Application.get_env(:endgate, [:api_client, :barentswatch, :retry_delay]) || 1000
  @pool_size Application.get_env(:endgate, [:api_client, :barentswatch, :pool_size]) || 10
  @mock_mode Application.get_env(:endgate, [:api_client, :barentswatch, :mock_mode]) || false
  
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
  
  # Client lifecycle
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    Logger.info("Starting Barentswatch API Client")
    
    # Initialize connection pool
    connection_pool = build_connection_pool()
    
    # Load API key from configuration
    api_key = Application.get_env(:endgate, [:api_client, :barentswatch, :api_key])
    
    state = %{
      connection_pool: connection_pool,
      api_key: api_key,
      rate_limits: %{},
      request_count: 0,
      last_request_time: nil,
      cache: %{}
    }
    
    # Start monitoring
    schedule_monitoring()
    
    {:ok, state}
  end
  
  # Public API methods
  def fetch(endpoint, params \\ %{}) do
    GenServer.call(__MODULE__, {:fetch, endpoint, params})
  end
  
  def fetch!(endpoint, params \\ %{}) do
    case fetch(endpoint, params) do
      {:ok, data} -> data
      {:error, reason, details} -> raise BarentswatchError, message: "API request failed: #{reason}", details: details
    end
  end
  
  def stream(endpoint, params \\ %{}) do
    GenServer.call(__MODULE__, {:stream, endpoint, params})
  end
  
  def clear_cache() do
    GenServer.cast(__MODULE__, :clear_cache)
  end
  
  def get_cache_stats() do
    GenServer.call(__MODULE__, :get_cache_stats)
  end
  
  # Configuration change handler
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer call handlers
  def handle_call({:fetch, endpoint, params}, _from, state) do
    # Check rate limits
    with {:ok, state} <- check_rate_limits(state) do
      # Try cache first
      case get_from_cache(state, endpoint, params) do
        {:ok, cached_data} ->
          {:reply, {:ok, cached_data}, state}
        
        :not_cached ->
          # Build and execute request
          case build_and_execute_request(endpoint, params, state) do
            {:ok, response, updated_state} ->
              # Cache the response
              updated_state = put_in_cache(updated_state, endpoint, params, response)
              {:reply, {:ok, response}, updated_state}
            
            {:error, reason, details, updated_state} ->
              {:reply, {:error, reason, details}, updated_state}
          end
      end
    else
      error_reason ->
        {:reply, error_reason, state}
    end
  end
  
  def handle_call({:stream, endpoint, params}, _from, state) do
    # For streaming, we return a stream that will make requests as needed
    stream = Stream.resource(
      fn -> {:ok, nil, %{}}
      end,
      fn _ ->
        case fetch(endpoint, params) do
          {:ok, data} -> {data, %{}}
          {:error, reason, _} -> {:halt, {:error, reason}}
        end
      end,
      fn _, _ -> nil end
    )
    
    {:reply, {:ok, stream}, state}
  end
  
  def handle_call(:get_cache_stats, _from, state) do
    cache_stats = %{
      size: map_size(state.cache),
      endpoints: Enum.count(Enum.uniq(Map.keys(state.cache)))
    }
    {:reply, cache_stats, state}
  end
  
  # GenServer cast handlers
  def handle_cast(:clear_cache, state) do
    updated_state = %{state | cache: %{}}
    Logger.info("Barentswatch API cache cleared")
    {:noreply, updated_state}
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    # Handle configuration changes
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  # Private implementation methods
  defp build_connection_pool() do
    # Configure Tesla with connection pooling
    Tesla.client([
      adapter: Tesla.Adapter.Hackney,
      pool: :barentswatch_api_pool,
      pool_size: @pool_size,
      timeout: @timeout,
      recvm_timeout: @timeout
    ])
  end
  
  defp build_and_execute_request(endpoint, params, state) do
    # Build the request
    {request, state} = build_request(endpoint, params, state)
    
    # Execute with retries
    execute_with_retries(request, state, 0)
  end
  
  defp build_request(endpoint, params, state) do
    # Construct the URL
    url = "#{@base_url}#{endpoint}"
    
    # Add API key to headers
    headers = [
      {"x-api-key", state.api_key},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
    
    # Add query parameters
    query = Enum.map(params, fn {k, v} -> {"#{k}", "#{v}"} end)
    
    # Create Tesla request
    request = Tesla.Request.new(:get, url, headers, query: query)
    
    {request, state}
  end
  
  defp execute_with_retries(request, state, attempt) do
    try do
      # Execute the request
      case Tesla.get(request) do
        %Tesla.Env{status: status, body: body} when status in [200, 201, 204] ->
          # Update request count and timing
          updated_state = update_request_stats(state)
          
          # Parse and validate response
          case parse_response(body) do
            {:ok, data} -> {:ok, data, updated_state}
            {:error, reason} -> {:error, :invalid_response, reason, updated_state}
          end
        
        %Tesla.Env{status: status, body: body} ->
          # Handle API errors
          error_reason = handle_api_error(status, body)
          
          if attempt < @max_retries && should_retry?(status) do
            # Exponential backoff
            delay = @retry_delay * (attempt + 1)
            Process.sleep(delay)
            execute_with_retries(request, state, attempt + 1)
          else
            {:error, error_reason, "API request failed after #{attempt} retries", state}
          end
      end
    rescue
      error ->
        if attempt < @max_retries do
          delay = @retry_delay * (attempt + 1)
          Process.sleep(delay)
          execute_with_retries(request, state, attempt + 1)
        else
          {:error, :connection_error, "#{inspect(error)}", state}
        end
    end
  end
  
  defp parse_response(body) do
    try do
      case Jason.decode(body) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, :json_parse_error, reason}
      end
    rescue
      error -> {:error, :parse_error, "#{inspect(error)}"}
    end
  end
  
  defp handle_api_error(status, body) do
    case status do
      401 -> :authentication_failed
      403 -> :forbidden
      404 -> :not_found
      429 -> :rate_limited
      500..599 -> :server_error
      _ -> :unknown_error
    end
  end
  
  defp should_retry?(status) do
    status in [429, 500, 502, 503, 504] || status >= 500
  end
  
  defp check_rate_limits(state) do
    # Implement rate limiting logic
    # For now, just increment counter
    updated_state = %{
      state | 
      request_count: state.request_count + 1,
      last_request_time: System.system_time(:millisecond)
    }
    {:ok, updated_state}
  end
  
  defp update_request_stats(state) do
    %{
      state | 
      request_count: state.request_count + 1,
      last_request_time: System.system_time(:millisecond)
    }
  end
  
  defp get_from_cache(state, endpoint, params, _max_age \\ nil) do
    # Simple cache key based on endpoint and params
    cache_key = generate_cache_key(endpoint, params)
    
    case Map.get(state.cache, cache_key) do
      nil -> :not_cached
      cached -> {:ok, cached.data}
    end
  end
  
  defp put_in_cache(state, endpoint, params, data) do
    cache_key = generate_cache_key(endpoint, params)
    
    cache_entry = %{
      data: data,
      timestamp: System.system_time(:second),
      ttl: Application.get_env(:endgate, [:data_processing, :cache_ttl]) || 3600
    }
    
    %{state | cache: Map.put(state.cache, cache_key, cache_entry)}
  end
  
  defp generate_cache_key(endpoint, params) do
    # Create a consistent cache key
    params_sorted = Enum.sort(params, fn {k1, _}, {k2, _} -> k1 <= k2 end)
    key_parts = [endpoint | Enum.map(params_sorted, fn {k, v} -> "#{k}=#{v}" end)]
    String.join(key_parts, "|")
  end
  
  defp handle_config_changes(state, changed, removed) do
    # Handle changes to API configuration
    case changed do
      %{"api_client" => %{"barentswatch" => new_config}} ->
        updated_state = %{
          state | 
          api_key: new_config["api_key"] || state.api_key
        }
        Logger.info("Barentswatch API configuration updated")
        updated_state
      
      _ ->
        state
    end
  end
  
  defp schedule_monitoring() do
    # Schedule periodic monitoring
    Process.send_after(self(), :monitor, 60_000)  # Every 60 seconds
  end
  
  def handle_info(:monitor, state) do
    # Log monitoring information
    Logger.debug("Barentswatch Client Monitor: #{inspect(get_monitoring_data(state))}")
    
    # Reschedule
    schedule_monitoring()
    
    {:noreply, state}
  end
  
  defp get_monitoring_data(state) do
    %{
      request_count: state.request_count,
      cache_size: map_size(state.cache),
      last_request: state.last_request_time,
      uptime: calculate_uptime()
    }
  end
  
  defp calculate_uptime() do
    # Calculate uptime since start
    # This would need to track start time in state
    0  # Placeholder
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Barentswatch API Client shutting down")
    :ok
  end
end

# Custom error for Barentswatch API
defmodule BarentswatchError do
  defexception [:message, :details]
end