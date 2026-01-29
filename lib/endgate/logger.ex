defmodule Endgate.Logger do
  @moduledoc """
  Comprehensive logging framework for the Endgate platform.
  
  This module provides centralized logging with support for different log levels,
  structured logging, log rotation, and integration with external logging systems.
  It extends the standard Elixir Logger with additional features specific to
  the Endgate platform.
  """
  
  use GenServer
  
  require Logger
  
  # Configuration
  @log_level Application.get_env(:endgate, [:logger, :level]) || :info
  @log_file Application.get_env(:endgate, [:logger, :file]) || "logs/endgate.log"
  @max_file_size Application.get_env(:endgate, [:logger, :max_file_size]) || 10_000_000  # 10MB
  @max_files Application.get_env(:endgate, [:logger, :max_files]) || 5
  @log_format Application.get_env(:endgate, [:logger, :format]) || :structured
  
  # Log levels
  @levels [:debug, :info, :warn, :error, :critical]
  
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
  
  # Logger lifecycle
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Starting Endgate Logger")
    
    # Configure standard Logger
    configure_standard_logger()
    
    state = %{
      log_buffer: [],
      stats: %{
        debug: 0,
        info: 0,
        warn: 0,
        error: 0,
        critical: 0,
        total: 0
      },
      config: %{
        level: @log_level,
        file: @log_file,
        max_size: @max_file_size,
        max_files: @max_files,
        format: @log_format
      }
    }
    
    # Schedule log rotation check
    schedule_rotation_check()
    
    {:ok, state}
  end
  
  # Public API methods
  def log(level, message, context \ %{}) do
    GenServer.cast(__MODULE__, {:log, level, message, context})
  end
  
  def debug(message, context \ %{}) do
    log(:debug, message, context)
  end
  
  def info(message, context \ %{}) do
    log(:info, message, context)
  end
  
  def warn(message, context \ %{}) do
    log(:warn, message, context)
  end
  
  def error(message, context \ %{}) do
    log(:error, message, context)
  end
  
  def critical(message, context \ %{}) do
    log(:critical, message, context)
  end
  
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def set_level(level) do
    GenServer.cast(__MODULE__, {:set_level, level})
  end
  
  def rotate_logs() do
    GenServer.cast(__MODULE__, :rotate_logs)
  end
  
  def config_change(changed, removed) do
    GenServer.cast(__MODULE__, {:config_change, changed, removed})
  end
  
  # GenServer callbacks
  def handle_cast({:log, level, message, context}, state) do
    # Validate log level
    if level in @levels and should_log?(level, state.config.level) do
      # Format the log message
      formatted_message = format_message(level, message, context, state.config.format)
      
      # Log to standard Logger
      apply(Logger, level, [formatted_message])
      
      # Update statistics
      updated_stats = update_stats(state.stats, level)
      
      # Add to buffer for potential file logging
      updated_buffer = [formatted_message | state.log_buffer]
      
      # Check if we need to flush buffer to file
      final_state = if length(updated_buffer) >= 100 do
        flush_buffer_to_file(%{state | log_buffer: updated_buffer, stats: updated_stats})
      else
        %{state | log_buffer: updated_buffer, stats: updated_stats}
      end
      
      {:noreply, final_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  def handle_cast({:set_level, level}, state) do
    if level in @levels do
      updated_config = %{state.config | level: level}
      updated_state = %{state | config: updated_config}
      
      # Reconfigure standard logger
      configure_standard_logger(level)
      
      Logger.info("Log level changed to: #{level}")
      {:noreply, updated_state}
    else
      Logger.warn("Invalid log level: #{level}")
      {:noreply, state}
    end
  end
  
  def handle_cast(:rotate_logs, state) do
    # Perform log rotation
    case rotate_log_files() do
      :ok ->
        Logger.info("Logs rotated successfully")
        {:noreply, %{state | log_buffer: []}}
      
      {:error, reason} ->
        Logger.error("Log rotation failed: #{reason}")
        {:noreply, state}
    end
  end
  
  def handle_cast({:config_change, changed, removed}, state) do
    updated_state = handle_config_changes(state, changed, removed)
    {:noreply, updated_state}
  end
  
  def handle_info(:check_rotation, state) do
    # Check if log rotation is needed
    case check_log_size() do
      :needs_rotation ->
        rotate_logs()
        {:noreply, state}
      
      :ok ->
        {:noreply, state}
    end
    
    # Reschedule check
    schedule_rotation_check()
  end
  
  # Private implementation methods
  defp configure_standard_logger(level \ @log_level) do
    # Configure the standard Elixir Logger
    config = [
      level: level,
      format: "$time $metadata[$level] $message\n",
      metadata: [:request_id, :user_id, :module, :function]
    ]
    
    Logger.configure(config)
  end
  
  defp should_log?(message_level, current_level) do
    # Check if message should be logged based on current level
    level_index = fn
      :debug -> 0
      :info -> 1
      :warn -> 2
      :error -> 3
      :critical -> 4
    end
    
    level_index.(message_level) >= level_index.(current_level)
  end
  
  defp format_message(level, message, context, format) do
    case format do
      :structured ->
        structured_format(level, message, context)
      
      :json ->
        json_format(level, message, context)
      
      _ ->
        simple_format(level, message, context)
    end
  end
  
  defp structured_format(level, message, context) do
    # Format as structured data
    timestamp = System.system_time(:second)
    
    %{
      timestamp: timestamp,
      level: level,
      message: message,
      context: context,
      module: context[:module] || __MODULE__,
      function: context[:function] || "unknown",
      process_id: self()
    }
    |> Jason.encode!()
  end
  
  defp json_format(level, message, context) do
    # Format as JSON with additional metadata
    structured_format(level, message, context)
  end
  
  defp simple_format(level, message, context) do
    # Simple text format
    timestamp = System.system_time(:second)
    context_str = if context == %{}, do: "", else: " | #{inspect(context)}"
    
    "[#{timestamp}] #{String.upcase(to_string(level))}: #{message}#{context_str}"
  end
  
  defp update_stats(stats, level) do
    %{stats | 
      level => stats[level] + 1,
      total: stats.total + 1
    }
  end
  
  defp flush_buffer_to_file(state) do
    # Write buffered logs to file
    case write_to_log_file(state.log_buffer) do
      :ok ->
        %{state | log_buffer: []}
      
      {:error, reason} ->
        Logger.error("Failed to flush log buffer: #{reason}")
        state
    end
  end
  
  defp write_to_log_file(messages) do
    # Ensure log directory exists
    log_dir = Path.dirname(@log_file)
    File.mkdir_p!(log_dir)
    
    # Append messages to log file
    case File.open(@log_file, [:append]) do
      {:ok, file} ->
        try do
          Enum.each(messages, fn message ->
            IO.write(file, "#{message}\n")
          end)
          File.close(file)
          :ok
        rescue
          error ->
            File.close(file)
            {:error, error}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp check_log_size() do
    # Check if log file needs rotation
    case File.stat(@log_file) do
      {:ok, stats} ->
        if stats.size > @max_file_size do
          :needs_rotation
        else
          :ok
        end
      
      {:error, _} ->
        :ok  # File doesn't exist or other error
    end
  end
  
  defp rotate_log_files() do
    # Rotate log files
    log_dir = Path.dirname(@log_file)
    log_base = Path.basename(@log_file, ".log")
    
    # Find existing rotated files
    existing_files = File.ls!(log_dir)
    |> Enum.filter(fn file -> String.starts_with?(file, log_base) and String.ends_with?(file, ".log") end)
    |> Enum.sort()
    
    # Rotate files (delete oldest if we have too many)
    case length(existing_files) >= @max_files do
      true ->
        # Delete oldest file
        oldest_file = hd(existing_files)
        File.rm!(Path.join(log_dir, oldest_file))
      
      false ->
        :ok
    end
    
    # Rename current log file
    timestamp = System.system_time(:second)
    rotated_name = "#{log_base}.#{timestamp}.log"
    
    try do
      File.rename!(@log_file, Path.join(log_dir, rotated_name))
      :ok
    rescue
      error ->
        {:error, error}
    end
  end
  
  defp schedule_rotation_check() do
    # Schedule next rotation check (every 5 minutes)
    Process.send_after(self(), :check_rotation, 300_000)
  end
  
  defp handle_config_changes(state, changed, _removed) do
    case changed do
      %{"logger" => new_config} ->
        # Update logger configuration
        updated_config = %{
          state.config
          | 
          level: new_config["level"] || state.config.level,
          file: new_config["file"] || state.config.file,
          max_size: new_config["max_file_size"] || state.config.max_size,
          max_files: new_config["max_files"] || state.config.max_files,
          format: new_config["format"] || state.config.format
        }
        
        # Reconfigure standard logger if level changed
        if updated_config.level != state.config.level do
          configure_standard_logger(updated_config.level)
        end
        
        Logger.info("Logger configuration updated")
        %{state | config: updated_config}
      
      _ ->
        state
    end
  end
  
  # Terminate callback
  def terminate(_reason, _state) do
    # Flush any remaining buffer before shutdown
    flush_buffer_to_file(_state)
    Logger.info("Endgate Logger shutting down")
    :ok
  end
  
  # Additional logging utilities
  def log_with_context(context, fun) do
    # Execute function and log with context
    try do
      result = fun.()
      info("Operation completed successfully", context)
      result
    rescue
      error ->
        error_msg = "Operation failed: #{inspect(error)}"
        error(error_msg, %{context | error: error})
        {:error, error}
    end
  end
  
  def time_and_log(message, context \ %{}, fun) do
    # Time an operation and log the duration
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      info("#{message} completed in #{duration}ms", context)
      result
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        error("#{message} failed after #{duration}ms: #{inspect(error)}", context)
        {:error, error}
    end
  end
  
  def log_api_call(module, function, params, fun) do
    # Log API calls with parameters and timing
    context = %{
      module: module,
      function: function,
      params: params,
      type: :api_call
    }
    
    time_and_log("API call: #{module}.#{function}", context, fun)
  end
end