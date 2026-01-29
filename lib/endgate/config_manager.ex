defmodule Endgate.ConfigManager do
  @moduledoc """
  Configuration management system for the Endgate platform.
  
  This module provides centralized configuration management with support for
  environment variables, configuration files, and runtime configuration changes.
  It handles configuration validation, change notifications, and provides
  a unified interface for all application components.
  """
  
  use GenServer
  
  require Logger
  
  # Configuration schema
  @config_schema %{
    api_client: %{
      barentswatch: %{
        base_url: :string,
        api_key: :string,
        timeout: :integer,
        max_retries: :integer,
        retry_delay: :integer,
        pool_size: :integer,
        mock_mode: :boolean
      }
    },
    data_processing: %{
      batch_size: :integer,
      max_demand: :integer,
      cache_ttl: :integer
    },
    realtime: %{
      max_message_rate: :integer,
      message_history_size: :integer,
      broadcast_interval: :integer
    },
    cache: %{
      default_ttl: :integer,
      max_cache_size: :integer,
      cleanup_interval: :integer
    },
    oban: %{
      queues: :map,
      max_attempts: :integer,
      backoff: :list
    }
  }
  
  # Default configuration
  @default_config %{
    api_client: %{
      barentswatch: %{
        base_url: "https://api.barentswatch.no",
        api_key: nil,
        timeout: 30000,
        max_retries: 3,
        retry_delay: 1000,
        pool_size: 10,
        mock_mode: false
      }
    },
    data_processing: %{
      batch_size: 100,
      max_demand: 1000,
      cache_ttl: 3600
    },
    realtime: %{
      max_message_rate: 100,
      message_history_size: 100,
      broadcast_interval: 1000
    },
    cache: %{
      default_ttl: 3600,
      max_cache_size: 1000,
      cleanup_interval: 3600
    },
    oban: %{
      queues: %{
        data_sync: 10,
        reports: 5,
        default: 5
      },
      max_attempts: 3,
      backoff: [:exponential, :seconds, 5]
    }
  }
  
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
  
  # Config manager lifecycle
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Starting Endgate Configuration Manager")
    
    # Load initial configuration
    initial_config = load_initial_config()
    
    # Validate configuration
    case validate_config(initial_config) do
      {:ok, validated_config} ->
        state = %{
          config: validated_config,
          subscribers: %{},
          change_history: [],
          last_updated: System.system_time(:second)
        }
        
        {:ok, state}
      
      {:error, errors} ->
        Logger.error("Configuration validation failed: #{inspect(errors)}")
        {:stop, :configuration_error}
    end
  end
  
  # Public API methods
  def get_config() do
    GenServer.call(__MODULE__, :get_config)
  end
  
  def get_config(key) do
    GenServer.call(__MODULE__, {:get_config, key})
  end
  
  def set_config(key, value) do
    GenServer.cast(__MODULE__, {:set_config, key, value})
  end
  
  def update_config(updates) do
    GenServer.cast(__MODULE__, {:update_config, updates})
  end
  
  def reset_config() do
    GenServer.cast(__MODULE__, :reset_config)
  end
  
  def validate_config(config) do
    GenServer.call(__MODULE__, {:validate_config, config})
  end
  
  def subscribe(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end
  
  def unsubscribe(pid) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid})
  end
  
  def get_change_history() do
    GenServer.call(__MODULE__, :get_change_history)
  end
  
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer callbacks
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end
  
  def handle_call({:get_config, key}, _from, state) do
    case get_nested_value(state.config, key) do
      nil -> {:reply, {:error, :key_not_found}, state}
      value -> {:reply, {:ok, value}, state}
    end
  end
  
  def handle_cast({:set_config, key, value}, state) do
    # Update specific configuration key
    case update_nested_value(state.config, key, value) do
      {:ok, updated_config} ->
        # Validate the updated config
        case validate_config(updated_config) do
          {:ok, validated_config} ->
            updated_state = update_state_with_new_config(state, validated_config, key)
            notify_subscribers(updated_state, key, value)
            {:noreply, updated_state}
          
          {:error, errors} ->
            Logger.error("Configuration update validation failed: #{inspect(errors)}")
            {:noreply, state}
        end
      
      {:error, reason} ->
        Logger.error("Failed to update config key #{key}: #{reason}")
        {:noreply, state}
    end
  end
  
  def handle_cast({:update_config, updates}, state) do
    # Update multiple configuration values
    case update_multiple_values(state.config, updates) do
      {:ok, updated_config} ->
        case validate_config(updated_config) do
          {:ok, validated_config} ->
            updated_state = update_state_with_new_config(state, validated_config, :multiple)
            
            # Notify subscribers about all changes
            Enum.each(Map.keys(updates), fn key ->
              value = get_nested_value(validated_config, key)
              notify_subscribers(updated_state, key, value)
            end)
            
            {:noreply, updated_state}
          
          {:error, errors} ->
            Logger.error("Configuration update validation failed: #{inspect(errors)}")
            {:noreply, state}
        end
      
      {:error, reason} ->
        Logger.error("Failed to update config: #{reason}")
        {:noreply, state}
    end
  end
  
  def handle_cast(:reset_config, state) do
    # Reset to default configuration
    case validate_config(@default_config) do
      {:ok, validated_config} ->
        updated_state = update_state_with_new_config(state, validated_config, :reset)
        Logger.info("Configuration reset to defaults")
        {:noreply, updated_state}
      
      {:error, errors} ->
        Logger.error("Default configuration validation failed: #{inspect(errors)}")
        {:noreply, state}
    end
  end
  
  def handle_call({:validate_config, config}, _from, _state) do
    validate_config(config)
  end
  
  def handle_cast({:subscribe, pid}, state) do
    updated_subscribers = Map.put(state.subscribers, pid, true)
    updated_state = %{state | subscribers: updated_subscribers}
    
    Logger.debug("Config: New subscriber #{inspect(pid)}")
    {:noreply, updated_state}
  end
  
  def handle_cast({:unsubscribe, pid}, state) do
    updated_subscribers = Map.delete(state.subscribers, pid)
    updated_state = %{state | subscribers: updated_subscribers}
    
    Logger.debug("Config: Subscriber removed #{inspect(pid)}")
    {:noreply, updated_state}
  end
  
  def handle_call(:get_change_history, _from, state) do
    {:reply, state.change_history, state}
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    # Handle external configuration changes (from application.env)
    updated_config = handle_external_config_changes(state.config, changed, removed)
    
    case validate_config(updated_config) do
      {:ok, validated_config} ->
        updated_state = update_state_with_new_config(state, validated_config, :external)
        
        # Notify about all changed keys
        Enum.each(Map.keys(changed), fn key ->
          value = get_nested_value(validated_config, key)
          notify_subscribers(updated_state, key, value)
        end)
        
        {:noreply, updated_state}
      
      {:error, errors} ->
        Logger.error("External configuration validation failed: #{inspect(errors)}")
        {:noreply, state}
    end
  end
  
  # Private implementation methods
  defp load_initial_config() do
    # Load configuration from multiple sources
    # Priority: environment variables > config files > defaults
    
    env_config = load_from_environment()
    file_config = load_from_files()
    
    # Merge configurations (later sources override earlier ones)
    @default_config
    |> Map.merge(file_config)
    |> Map.merge(env_config)
  end
  
  defp load_from_environment() do
    # Load configuration from environment variables
    # This is a simplified version - real implementation would be more comprehensive
    
    api_key = System.get_env("BARENTWATCH_API_KEY")
    mock_mode = System.get_env("MOCK_MODE")
    
    %{
      api_client: %{
        barentswatch: %{
          api_key: api_key,
          mock_mode: mock_mode == "true"
        }
      }
    }
  end
  
  defp load_from_files() do
    # Load configuration from files
    # This would read from config files in different environments
    
    # For now, we'll return empty as we're using the application config system
    %{}
  end
  
  defp validate_config(config) do
    # Validate configuration against schema
    errors = []
    
    # Check required fields
    errors = validate_required_fields(config, @config_schema, errors, [])
    
    # Check data types
    errors = validate_data_types(config, @config_schema, errors, [])
    
    # Check value ranges
    errors = validate_value_ranges(config, errors, [])
    
    if errors == [] do
      {:ok, config}
    else
      {:error, errors}
    end
  end
  
  defp validate_required_fields(config, schema, errors, path) do
    case {config, schema} do
      {%{}, %{}} ->
        # Both are maps, validate each key
        Enum.reduce(Map.keys(schema), errors, fn key, acc ->
          if Map.has_key?(config, key) do
            validate_required_fields(Map.get(config, key), Map.get(schema, key), acc, path ++ [key])
          else
            acc ++ [%{path: path ++ [key], error: :required_field_missing}]
          end
        end)
      
      _ ->
        errors
    end
  end
  
  defp validate_data_types(config, schema, errors, path) do
    case {config, schema} do
      {%{}, %{}} ->
        Enum.reduce(Map.keys(schema), errors, fn key, acc ->
          expected_type = Map.get(schema, key)
          actual_value = Map.get(config, key)
          
          case validate_type(actual_value, expected_type) do
            :ok ->
              validate_data_types(actual_value, expected_type, acc, path ++ [key])
            
            {:error, error_msg} ->
              acc ++ [%{path: path ++ [key], error: error_msg}]
          end
        end)
      
      _ ->
        errors
    end
  end
  
  defp validate_type(value, :string) do
    if is_binary(value), do: :ok, else: {:error, :expected_string}
  end
  
  defp validate_type(value, :integer) do
    if is_integer(value), do: :ok, else: {:error, :expected_integer}
  end
  
  defp validate_type(value, :boolean) do
    if is_boolean(value), do: :ok, else: {:error, :expected_boolean}
  end
  
  defp validate_type(value, :map) do
    if is_map(value), do: :ok, else: {:error, :expected_map}
  end
  
  defp validate_type(value, :list) do
    if is_list(value), do: :ok, else: {:error, :expected_list}
  end
  
  defp validate_type(_value, _type), do: :ok
  
  defp validate_value_ranges(config, errors, path) do
    # Validate specific value ranges
    case Map.get(config, [:api_client, :barentswatch, :timeout]) do
      timeout when is_integer(timeout) and timeout < 1000 ->
        errors ++ [%{path: path ++ [:api_client, :barentswatch, :timeout], error: :timeout_too_short}]
      
      _ ->
        errors
    end
  end
  
  defp update_state_with_new_config(state, new_config, change_source) do
    change_record = %{
      timestamp: System.system_time(:second),
      source: change_source,
      changes: compare_configs(state.config, new_config)
    }
    
    %{state | 
      config: new_config,
      change_history: [change_record | state.change_history],
      last_updated: System.system_time(:second)
    }
  end
  
  defp compare_configs(old_config, new_config) do
    # Find differences between old and new config
    find_differences(old_config, new_config, [])
  end
  
  defp find_differences(%{} = old, %{} = new, path) do
    all_keys = Map.keys(old) ++ Map.keys(new) |> Enum.uniq()
    
    Enum.flat_map(all_keys, fn key ->
      old_value = Map.get(old, key)
      new_value = Map.get(new, key)
      
      if old_value != new_value do
        if is_map(old_value) and is_map(new_value) do
          find_differences(old_value, new_value, path ++ [key])
        else
          [%{path: path ++ [key], old: old_value, new: new_value}]
        end
      else
        []
      end
    end)
  end
  
  defp find_differences(_, _, _), do: []
  
  defp notify_subscribers(state, key, value) do
    # Notify all subscribers about configuration change
    Enum.each(Map.keys(state.subscribers), fn pid ->
      try do
        send(pid, {:config_change, key, value})
      rescue
        _ -> :ok  # Ignore notification errors
      end
    end)
    
    Logger.debug("Config: Notified subscribers about change to #{key}")
  end
  
  defp handle_external_config_changes(config, changed, removed) do
    # Apply external configuration changes
    # This handles changes from the application environment
    
    # First, remove any deleted keys
    updated_config = remove_deleted_keys(config, removed, [])
    
    # Then, apply changed values
    updated_config = apply_changed_values(updated_config, changed, [])
    
    updated_config
  end
  
  defp remove_deleted_keys(config, removed, path) do
    case {config, removed} do
      {%{}, %{}} ->
        Enum.reduce(Map.keys(removed), config, fn key, acc ->
          Map.delete(acc, key)
        end)
      
      _ ->
        config
    end
  end
  
  defp apply_changed_values(config, changed, path) do
    case {config, changed} do
      {%{}, %{}} ->
        Enum.reduce(Map.keys(changed), config, fn key, acc ->
          Map.put(acc, key, Map.get(changed, key))
        end)
      
      _ ->
        config
    end
  end
  
  defp get_nested_value(config, key) when is_list(key) do
    Enum.reduce(key, config, fn k, acc ->
      case acc do
        nil -> nil
        %{} -> Map.get(acc, k)
        _ -> nil
      end
    end)
  end
  
  defp get_nested_value(config, key) when is_atom(key) do
    Map.get(config, key)
  end
  
  defp get_nested_value(config, key) when is_binary(key) do
    # Convert string key to atom and try to get value
    key_path = String.split(key, ".")
    get_nested_value(config, key_path)
  end
  
  defp update_nested_value(config, key, value) when is_list(key) do
    case key do
      [] -> {:error, :empty_key_path}
      [head | tail] ->
        case Map.get(config, head) do
          nil when tail == [] -> {:ok, Map.put(config, head, value)}
          nil -> {:error, :intermediate_key_missing}
          sub_config ->
            case update_nested_value(sub_config, tail, value) do
              {:ok, updated_sub} -> {:ok, Map.put(config, head, updated_sub)}
              error -> error
            end
        end
    end
  end
  
  defp update_nested_value(config, key, value) when is_atom(key) do
    {:ok, Map.put(config, key, value)}
  end
  
  defp update_nested_value(config, key, value) when is_binary(key) do
    key_path = String.split(key, ".")
    update_nested_value(config, key_path, value)
  end
  
  defp update_multiple_values(config, updates) do
    Enum.reduce(Map.keys(updates), {:ok, config}, fn key, {:ok, acc} ->
      value = Map.get(updates, key)
      update_nested_value(acc, key, value)
    end)
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Endgate Configuration Manager shutting down")
    :ok
  end
end