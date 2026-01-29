defmodule Endgate.ErrorHandler do
  @moduledoc """
  Comprehensive error handling module for the Endgate platform.
  
  This module provides centralized error handling, logging, and recovery
  mechanisms for all components of the application.
  """
  
  require Logger
  
  # Error categories
  @api_errors [:connection_error, :authentication_error, :rate_limit_error, :invalid_response, :timeout]
  @data_errors [:validation_error, :transformation_error, :enrichment_error, :missing_data]
  @system_errors [:configuration_error, :resource_error, :processing_error, :storage_error]
  @realtime_errors [:broadcast_error, :subscription_error, :rate_limit_exceeded]
  
  # Public API
  def handle_error(error, context \ %{}) do
    # Classify and handle the error
    case classify_error(error) do
      {:api_error, category} -> handle_api_error(error, category, context)
      {:data_error, category} -> handle_data_error(error, category, context)
      {:system_error, category} -> handle_system_error(error, category, context)
      {:realtime_error, category} -> handle_realtime_error(error, category, context)
      {:unknown_error, _} -> handle_unknown_error(error, context)
    end
  end
  
  def log_error(error, context \ %{}, level \ :error) do
    # Format error for logging
    formatted_error = format_error(error, context)
    
    # Log at appropriate level
    apply(Logger, level, [formatted_error])
    
    formatted_error
  end
  
  def recover_from_error(error, context \ %{}, recovery_strategy) do
    # Attempt to recover from the error
    case recovery_strategy do
      :retry -> attempt_recovery_with_retry(error, context)
      :fallback -> attempt_recovery_with_fallback(error, context)
      :notify -> attempt_recovery_with_notification(error, context)
      :ignore -> attempt_recovery_with_ignore(error, context)
    end
  end
  
  def create_error_response(error, context \ %{}) do
    # Create standardized error response
    case classify_error(error) do
      {:api_error, category} ->
        %{status: :error, type: :api_error, category: category, message: error_message(error), context: context}
      
      {:data_error, category} ->
        %{status: :error, type: :data_error, category: category, message: error_message(error), context: context}
      
      {:system_error, category} ->
        %{status: :error, type: :system_error, category: category, message: error_message(error), context: context}
      
      {:realtime_error, category} ->
        %{status: :error, type: :realtime_error, category: category, message: error_message(error), context: context}
      
      {:unknown_error, _} ->
        %{status: :error, type: :unknown_error, message: error_message(error), context: context}
    end
  end
  
  # Error classification
  defp classify_error({:error, category, _} = error) when category in @api_errors do
    {:api_error, category}
  end
  
  defp classify_error({:error, category, _} = error) when category in @data_errors do
    {:data_error, category}
  end
  
  defp classify_error({:error, category, _} = error) when category in @system_errors do
    {:system_error, category}
  end
  
  defp classify_error({:error, category, _} = error) when category in @realtime_errors do
    {:realtime_error, category}
  end
  
  defp classify_error(%BarentswatchError{} = error) do
    {:api_error, :barentswatch_error}
  end
  
  defp classify_error(%RuntimeError{} = error) do
    {:system_error, :runtime_error}
  end
  
  defp classify_error(%ArgumentError{} = error) do
    {:data_error, :argument_error}
  end
  
  defp classify_error(%{message: message}) when is_binary(message) do
    case message do
      msg when String.contains?(msg, "connection") -> {:api_error, :connection_error}
      msg when String.contains?(msg, "authentication") -> {:api_error, :authentication_error}
      msg when String.contains?(msg, "rate limit") -> {:api_error, :rate_limit_error}
      msg when String.contains?(msg, "validation") -> {:data_error, :validation_error}
      msg when String.contains?(msg, "transformation") -> {:data_error, :transformation_error}
      _ -> {:unknown_error, :unclassified}
    end
  end
  
  defp classify_error(_error), do: {:unknown_error, :unclassified}
  
  # Error handlers
  defp handle_api_error(error, category, context) do
    # Handle API-related errors
    error_data = %{type: :api_error, category: category, error: error, context: context}
    
    # Log the error
    log_error(error, context, :error)
    
    # Attempt recovery based on error type
    case category do
      :rate_limit_error ->
        # Implement exponential backoff for rate limiting
        recovery_strategy = :retry
      
      :connection_error ->
        # Attempt to reconnect or use cached data
        recovery_strategy = :fallback
      
      _ ->
        # Default recovery strategy
        recovery_strategy = :notify
    end
    
    # Return error response with recovery strategy
    %{error_data | recovery_strategy: recovery_strategy}
  end
  
  defp handle_data_error(error, category, context) do
    # Handle data processing errors
    error_data = %{type: :data_error, category: category, error: error, context: context}
    
    # Log the error
    log_error(error, context, :warn)
    
    # Data errors are often non-critical, so we can continue with partial data
    recovery_strategy = :fallback
    
    %{error_data | recovery_strategy: recovery_strategy}
  end
  
  defp handle_system_error(error, category, context) do
    # Handle system-level errors
    error_data = %{type: :system_error, category: category, error: error, context: context}
    
    # Log the error
    log_error(error, context, :error)
    
    # System errors may require more aggressive recovery
    recovery_strategy = case category do
      :configuration_error -> :notify
      :resource_error -> :retry
      _ -> :notify
    end
    
    %{error_data | recovery_strategy: recovery_strategy}
  end
  
  defp handle_realtime_error(error, category, context) do
    # Handle real-time system errors
    error_data = %{type: :realtime_error, category: category, error: error, context: context}
    
    # Log the error
    log_error(error, context, :warn)
    
    # Realtime errors can often be ignored or retried
    recovery_strategy = :retry
    
    %{error_data | recovery_strategy: recovery_strategy}
  end
  
  defp handle_unknown_error(error, context) do
    # Handle unknown/unclassified errors
    error_data = %{type: :unknown_error, error: error, context: context}
    
    # Log the error
    log_error(error, context, :error)
    
    # Unknown errors should be notified for investigation
    recovery_strategy = :notify
    
    %{error_data | recovery_strategy: recovery_strategy}
  end
  
  # Recovery strategies
  defp attempt_recovery_with_retry(error, context) do
    # Implement retry logic with exponential backoff
    attempt = context[:attempt] || 1
    max_attempts = context[:max_attempts] || 3
    
    if attempt < max_attempts do
      delay = calculate_backoff_delay(attempt)
      
      Logger.info("Attempting recovery (attempt #{attempt}/#{max_attempts}) after #{delay}ms")
      
      # Sleep and retry
      Process.sleep(delay)
      
      %{status: :retry, delay: delay, next_attempt: attempt + 1}
    else
      Logger.warn("Max recovery attempts reached for: #{inspect(error)}")
      %{status: :failed, reason: :max_attempts_reached}
    end
  end
  
  defp attempt_recovery_with_fallback(error, context) do
    # Implement fallback logic
    fallback_data = context[:fallback_data] || %{}
    
    Logger.info("Using fallback data due to error: #{inspect(error)}")
    
    %{status: :fallback, data: fallback_data}
  end
  
  defp attempt_recovery_with_notification(error, context) do
    # Implement notification logic
    notification_target = context[:notification_target] || :system_admin
    
    Logger.warn("Error requires notification: #{inspect(error)}")
    
    # In a real system, this would send a notification
    # For now, we'll just log it
    
    %{status: :notified, target: notification_target}
  end
  
  defp attempt_recovery_with_ignore(error, context) do
    # Implement ignore strategy
    Logger.debug("Ignoring error: #{inspect(error)}")
    
    %{status: :ignored}
  end
  
  # Helper functions
  defp error_message(error) do
    case error do
      {:error, _, message} when is_binary(message) -> message
      %{message: message} when is_binary(message) -> message
      tuple when is_tuple(tuple) -> inspect(tuple)
      _ -> to_string(error)
    end
  end
  
  defp format_error(error, context) do
    # Format error for logging
    error_msg = error_message(error)
    context_str = if context == %{}, do: "", else: " | Context: #{inspect(context)}"
    
    "[ERROR] #{error_msg}#{context_str}"
  end
  
  defp calculate_backoff_delay(attempt) do
    # Exponential backoff: 2^attempt * 100ms, capped at 5 seconds
    delay = :math.pow(2, attempt) * 100
    min(delay, 5000)
  end
  
  # Error monitoring and metrics
  def track_error(error, context \ %{}) do
    # Track error for monitoring and metrics
    classified = classify_error(error)
    
    # Increment error counters
    # This would be implemented with telemetry or metrics system
    
    Logger.debug("Tracking error: #{inspect(classified)}")
    
    :ok
  end
  
  def get_error_metrics() do
    # Return error metrics
    # This would be implemented with a proper metrics system
    %{
      total_errors: 0,
      by_category: %{
        api: 0,
        data: 0,
        system: 0,
        realtime: 0,
        unknown: 0
      }
    }
  end
end