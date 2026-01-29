defmodule Endgate.Realtime.Broadcaster do
  @moduledoc """
  Real-time data broadcasting system.
  
  This module handles real-time data distribution to connected clients
  using Phoenix PubSub. It supports multiple topics and manages
  client subscriptions, rate limiting, and message history.
  """
  
  use GenServer
  use Phoenix.PubSub
  
  require Logger
  
  # Configuration
  @max_message_rate Application.get_env(:endgate, [:realtime, :max_message_rate]) || 100
  @message_history_size Application.get_env(:endgate, [:realtime, :message_history_size]) || 100
  @broadcast_interval Application.get_env(:endgate, [:realtime, :broadcast_interval]) || 1000
  
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
  
  # Broadcaster lifecycle
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Starting Real-time Broadcaster")
    
    # Initialize PubSub
    Phoenix.PubSub.start_link([])
    
    state = %{
      subscriptions: %{},
      message_history: %{},
      rate_limits: %{},
      metrics: %{
        messages_sent: 0,
        clients_connected: 0,
        active_topics: 0
      }
    }
    
    # Start broadcast loop
    schedule_broadcast()
    
    {:ok, state}
  end
  
  # Public API methods
  def subscribe(topic) do
    GenServer.cast(__MODULE__, {:subscribe, topic})
  end
  
  def unsubscribe(topic) do
    GenServer.cast(__MODULE__, {:unsubscribe, topic})
  end
  
  def broadcast(topic, message) do
    GenServer.cast(__MODULE__, {:broadcast, topic, message})
  end
  
  def get_subscriptions() do
    GenServer.call(__MODULE__, :get_subscriptions)
  end
  
  def get_metrics() do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  def get_message_history(topic) do
    GenServer.call(__MODULE__, {:get_message_history, topic})
  end
  
  def clear_message_history() do
    GenServer.cast(__MODULE__, :clear_message_history)
  end
  
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer callbacks
  def handle_cast({:subscribe, topic}, state) do
    # Add subscription
    updated_subscriptions = Map.update(state.subscriptions, topic, [self()], fn clients ->
      [self() | clients] |> Enum.uniq()
    end)
    
    # Update metrics
    updated_metrics = %{
      state.metrics
      | 
      clients_connected: state.metrics.clients_connected + 1,
      active_topics: length(updated_subscriptions)
    }
    
    updated_state = %{
      state
      | 
      subscriptions: updated_subscriptions,
      metrics: updated_metrics
    }
    
    Logger.debug("Subscribed to topic: #{topic}")
    {:noreply, updated_state}
  end
  
  def handle_cast({:unsubscribe, topic}, state) do
    # Remove subscription
    updated_subscriptions = Map.update(state.subscriptions, topic, [self()], fn clients ->
      clients -- [self()]
    end)
    
    # Clean up empty topics
    updated_subscriptions = Map.filter(updated_subscriptions, fn {_, clients} ->
      clients != []
    end)
    
    # Update metrics
    updated_metrics = %{
      state.metrics
      | 
      clients_connected: max(0, state.metrics.clients_connected - 1),
      active_topics: length(updated_subscriptions)
    }
    
    updated_state = %{
      state
      | 
      subscriptions: updated_subscriptions,
      metrics: updated_metrics
    }
    
    Logger.debug("Unsubscribed from topic: #{topic}")
    {:noreply, updated_state}
  end
  
  def handle_cast({:broadcast, topic, message}, state) do
    # Format and validate message
    case format_message(topic, message) do
      {:ok, formatted_message} ->
        # Check rate limits
        if check_rate_limit(state, topic) do
          # Add to message history
          updated_state = add_to_history(state, topic, formatted_message)
          
          # Broadcast to subscribers
          broadcast_to_subscribers(updated_state, topic, formatted_message)
          
          # Update metrics
          final_state = update_metrics(updated_state, :message_sent)
          
          {:noreply, final_state}
        else
          Logger.warn("Rate limit exceeded for topic: #{topic}")
          {:noreply, update_metrics(state, :rate_limited)}
        end
      
      {:error, reason} ->
        Logger.warn("Message formatting failed: #{reason}")
        {:noreply, update_metrics(state, :format_error)}
    end
  end
  
  def handle_call(:get_subscriptions, _from, state) do
    {:reply, state.subscriptions, state}
  end
  
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  def handle_call({:get_message_history, topic}, _from, state) do
    history = Map.get(state.message_history, topic, [])
    {:reply, history, state}
  end
  
  def handle_cast(:clear_message_history, state) do
    updated_state = %{state | message_history: %{}}
    Logger.info("Real-time message history cleared")
    {:noreply, updated_state}
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  def handle_info(:broadcast, state) do
    # Periodic broadcast for heartbeat/keepalive
    broadcast_system_message(state, "system:heartbeat", %{status: "ok", timestamp: System.system_time(:second)})
    
    # Reschedule
    schedule_broadcast()
    
    {:noreply, state}
  end
  
  # Private implementation methods
  defp broadcast_to_subscribers(state, topic, message) do
    # Get subscribers for this topic
    case Map.get(state.subscriptions, topic) do
      nil ->
        state  # No subscribers
      
      subscribers when subscribers != [] ->
        # Send message to each subscriber
        Enum.each(subscribers, fn pid ->
          try do
            send(pid, {:broadcast, topic, message})
          rescue
            _ -> :ok  # Ignore send errors
          end
        end)
        
        state
    end
  end
  
  defp format_message(topic, message) do
    # Ensure message is a map and add metadata
    try do
      formatted = case message do
        %{} = map -> map
        _ -> %{data: message}
      end
      
      # Add standard metadata
      with_timestamp = Map.put(formatted, :timestamp, System.system_time(:second))
      with_topic = Map.put(with_timestamp, :topic, topic)
      
      {:ok, with_topic}
    rescue
      error ->
        {:error, :formatting_error, error: error}
    end
  end
  
  defp check_rate_limit(state, topic) do
    # Simple rate limiting implementation
    current_time = System.system_time(:millisecond)
    
    case Map.get(state.rate_limits, topic) do
      nil ->
        # First message for this topic
        updated_limits = Map.put(state.rate_limits, topic, %{count: 1, last_time: current_time})
        {:ok, updated_limits}
      
      %{count: count, last_time: last_time} ->
        # Check if we're within rate limit
        time_diff = current_time - last_time
        
        if time_diff < 1000 and count >= @max_message_rate do
          :rate_limited
        else
          # Reset count if it's been more than a second
          if time_diff >= 1000 do
            updated_limits = Map.put(state.rate_limits, topic, %{count: 1, last_time: current_time})
            {:ok, updated_limits}
          else
            updated_limits = Map.put(state.rate_limits, topic, %{count: count + 1, last_time: last_time})
            {:ok, updated_limits}
          end
        end
    end
  end
  
  defp add_to_history(state, topic, message) do
    # Add message to history, respecting size limits
    current_history = Map.get(state.message_history, topic, [])
    
    # Trim history if it's too large
    trimmed_history = if length(current_history) >= @message_history_size do
      current_history |> Enum.take(-(@message_history_size - 1))
    else
      current_history
    end
    
    # Add new message
    updated_history = [message | trimmed_history]
    
    %{state | message_history: Map.put(state.message_history, topic, updated_history)}
  end
  
  defp update_metrics(state, event) do
    case event do
      :message_sent ->
        %{state | metrics: %{state.metrics | messages_sent: state.metrics.messages_sent + 1}}
      
      :rate_limited ->
        %{state | metrics: %{state.metrics | rate_limited_messages: (state.metrics.rate_limited_messages || 0) + 1}}
      
      :format_error ->
        %{state | metrics: %{state.metrics | format_errors: (state.metrics.format_errors || 0) + 1}}
    end
  end
  
  defp broadcast_system_message(state, topic, message) do
    # Broadcast system messages to all subscribers
    case format_message(topic, message) do
      {:ok, formatted} ->
        # Broadcast to all topics
        Map.keys(state.subscriptions)
        |> Enum.each(fn topic_key ->
          broadcast_to_subscribers(state, topic_key, formatted)
        end)
        
        state
      
      {:error, _} ->
        state
    end
  end
  
  defp schedule_broadcast() do
    # Schedule next broadcast
    Process.send_after(self(), :broadcast, @broadcast_interval)
  end
  
  defp handle_config_changes(state, changed, _removed) do
    case changed do
      %{"realtime" => new_config} ->
        # Update configuration
        updated_state = %{
          state | 
          config: Map.merge(state.config || %{}, new_config)
        }
        
        # Apply new rate limit if changed
        if Map.has_key?(new_config, "max_message_rate") do
          new_rate_limit = new_config["max_message_rate"]
          Logger.info("Updated realtime message rate limit to: #{new_rate_limit}")
        end
        
        Logger.info("Real-time Broadcaster configuration updated")
        updated_state
      
      _ ->
        state
    end
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    Logger.info("Real-time Broadcaster shutting down")
    :ok
  end
end