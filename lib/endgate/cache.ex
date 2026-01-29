defmodule Endgate.Cache do
  @moduledoc """
  Centralized caching system for the Endgate platform.
  
  This module provides a unified caching interface that can be used by
  all components of the application. It supports multiple cache backends
  and provides cache invalidation, TTL management, and cache statistics.
  """
  
  use GenServer
  
  require Logger
  
  # Configuration
  @default_ttl Application.get_env(:endgate, [:cache, :default_ttl]) || 3600
  @max_cache_size Application.get_env(:endgate, [:cache, :max_cache_size]) || 1000
  @cleanup_interval Application.get_env(:endgate, [:cache, :cleanup_interval]) || 3600
  
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
  
  # Cache lifecycle
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Starting Endgate Cache System")
    
    state = %{
      cache: %{},
      stats: %{
        hits: 0,
        misses: 0,
        evictions: 0,
        current_size: 0,
        max_size: @max_cache_size
      },
      ttl: @default_ttl
    }
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, state}
  end
  
  # Public API methods
  def put(key, value, ttl \ nil) do
    GenServer.cast(__MODULE__, {:put, key, value, ttl})
  end
  
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end
  
  def delete(key) do
    GenServer.cast(__MODULE__, {:delete, key})
  end
  
  def clear() do
    GenServer.cast(__MODULE__, :clear)
  end
  
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def set_ttl(ttl) do
    GenServer.cast(__MODULE__, {:set_ttl, ttl})
  end
  
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer callbacks
  def handle_cast({:put, key, value, ttl}, state) do
    # Add or update cache entry
    current_time = System.system_time(:second)
    entry_ttl = ttl || state.ttl
    
    cache_entry = %{
      value: value,
      timestamp: current_time,
      ttl: entry_ttl,
      expires_at: current_time + entry_ttl
    }
    
    # Check if we need to evict old entries
    updated_state = if state.stats.current_size >= state.stats.max_size do
      evict_old_entries(state, 10)  # Evict 10% of cache
    else
      state
    end
    
    # Add new entry
    updated_cache = Map.put(updated_state.cache, key, cache_entry)
    updated_stats = %{
      updated_state.stats
      | 
      current_size: updated_state.stats.current_size + 1
    }
    
    final_state = %{updated_state | cache: updated_cache, stats: updated_stats}
    
    Logger.debug("Cache: Added key #{key}")
    {:noreply, final_state}
  end
  
  def handle_call({:get, key}, _from, state) do
    # Retrieve cache entry
    case Map.get(state.cache, key) do
      nil ->
        # Cache miss
        updated_stats = %{
          state.stats
          | 
          misses: state.stats.misses + 1
        }
        
        Logger.debug("Cache: Miss for key #{key}")
        {:reply, :not_found, %{state | stats: updated_stats}}
      
      entry ->
        # Check if entry is expired
        if is_expired?(entry) do
          # Remove expired entry
          updated_cache = Map.delete(state.cache, key)
          updated_stats = %{
            state.stats
            | 
            misses: state.stats.misses + 1,
            current_size: state.stats.current_size - 1
          }
          
          Logger.debug("Cache: Expired entry removed for key #{key}")
          {:reply, :expired, %{state | cache: updated_cache, stats: updated_stats}}
        else
          # Cache hit
          updated_stats = %{
            state.stats
            | 
            hits: state.stats.hits + 1
          }
          
          Logger.debug("Cache: Hit for key #{key}")
          {:reply, {:ok, entry.value}, %{state | stats: updated_stats}}
        end
    end
  end
  
  def handle_cast({:delete, key}, state) do
    # Remove cache entry
    case Map.get(state.cache, key) do
      nil ->
        state  # Key doesn't exist
      
      _ ->
        updated_cache = Map.delete(state.cache, key)
        updated_stats = %{
          state.stats
          | 
          current_size: state.stats.current_size - 1
        }
        
        Logger.debug("Cache: Deleted key #{key}")
        %{state | cache: updated_cache, stats: updated_stats}
    end
    
    {:noreply, state}
  end
  
  def handle_cast(:clear, state) do
    updated_state = %{state | cache: %{}, stats: %{state.stats | current_size: 0}}
    Logger.info("Cache: Cleared all entries")
    {:noreply, updated_state}
  end
  
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  def handle_cast({:set_ttl, ttl}, state) do
    updated_state = %{state | ttl: ttl}
    Logger.info("Cache: Updated default TTL to #{ttl} seconds")
    {:noreply, updated_state}
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  def handle_info(:cleanup, state) do
    # Perform cache cleanup
    updated_state = cleanup_expired_entries(state)
    
    # Reschedule cleanup
    schedule_cleanup()
    
    {:noreply, updated_state}
  end
  
  # Private implementation methods
  defp is_expired?(entry) do
    current_time = System.system_time(:second)
    current_time > entry.expires_at
  end
  
  defp evict_old_entries(state, percentage) do
    # Evict oldest entries to make room for new ones
    cache_size = state.stats.current_size
    entries_to_evict = max(1, div(cache_size * percentage, 100))
    
    # Sort entries by access time (oldest first)
    sorted_entries = state.cache
    |> Enum.sort_by(fn {_key, entry} -> entry.timestamp end)
    
    # Get keys of oldest entries
    keys_to_evict = sorted_entries
    |> Enum.take(entries_to_evict)
    |> Enum.map(fn {key, _} -> key end)
    
    # Remove entries
    updated_cache = Enum.reduce(keys_to_evict, state.cache, fn key, cache ->
      Map.delete(cache, key)
    end)
    
    updated_stats = %{
      state.stats
      | 
      evictions: state.stats.evictions + length(keys_to_evict),
      current_size: state.stats.current_size - length(keys_to_evict)
    }
    
    Logger.info("Cache: Evicted #{length(keys_to_evict)} old entries")
    
    %{state | cache: updated_cache, stats: updated_stats}
  end
  
  defp cleanup_expired_entries(state) do
    # Remove all expired entries
    current_time = System.system_time(:second)
    
    {expired_keys, valid_entries} = state.cache
    |> Enum.partition(fn {_key, entry} -> is_expired?(entry) end)
    
    expired_count = length(expired_keys)
    
    if expired_count > 0 do
      updated_cache = Enum.into(valid_entries, %{})
      
      updated_stats = %{
        state.stats
        | 
        evictions: state.stats.evictions + expired_count,
        current_size: state.stats.current_size - expired_count
      }
      
      Logger.info("Cache: Cleaned up #{expired_count} expired entries")
      
      %{state | cache: updated_cache, stats: updated_stats}
    else
      Logger.debug("Cache: No expired entries found")
      state
    end
  end
  
  defp schedule_cleanup() do
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval * 1000)
  end
  
  defp handle_config_changes(state, changed, _removed) do
    case changed do
      %{"cache" => new_config} ->
        # Update cache configuration
        updated_state = %{
          state | 
          ttl: new_config["default_ttl"] || state.ttl,
          stats: %{
            state.stats
            | 
            max_size: new_config["max_cache_size"] || state.stats.max_size
          }
        }
        
        Logger.info("Cache configuration updated")
        updated_state
      
      _ ->
        state
    end
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Endgate Cache System shutting down")
    :ok
  end
  
  # Additional cache utilities
  def get_all_keys() do
    GenServer.call(__MODULE__, :get_all_keys)
  end
  
  def get_multiple(keys) do
    GenServer.call(__MODULE__, {:get_multiple, keys})
  end
  
  def delete_multiple(keys) do
    GenServer.cast(__MODULE__, {:delete_multiple, keys})
  end
  
  def handle_call(:get_all_keys, _from, state) do
    keys = Map.keys(state.cache)
    {:reply, keys, state}
  end
  
  def handle_call({:get_multiple, keys}, _from, state) do
    results = Enum.map(keys, fn key ->
      case Map.get(state.cache, key) do
        nil -> {:not_found, key}
        entry -> if is_expired?(entry), do: {:expired, key}, else: {:ok, key, entry.value}
      end
    end)
    
    {:reply, results, state}
  end
  
  def handle_cast({:delete_multiple, keys}, state) do
    updated_cache = Enum.reduce(keys, state.cache, fn key, cache ->
      Map.delete(cache, key)
    end)
    
    evicted_count = Enum.count(keys, fn key -> Map.has_key?(state.cache, key) end)
    
    updated_stats = %{
      state.stats
      | 
      current_size: state.stats.current_size - evicted_count
    }
    
    Logger.info("Cache: Deleted #{evicted_count} entries")
    
    {:noreply, %{state | cache: updated_cache, stats: updated_stats}}
  end
end