defmodule EngineeringAnalyticsTerminal.CLI do
  @moduledoc """
  Command Line Interface using GenServer.
  
  This module provides an interactive interface for accessing
  BarentsWatch data and running analytics.
  """
  
  use GenServer
  
  alias EngineeringAnalyticsTerminal.BarentsWatch.Client
  
  # Client API
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end
  
  def start_link do
    start_link([])
  end
  
  def start_interactive do
    GenServer.cast(__MODULE__, :start_interactive)
  end
  
  def stop do
    GenServer.cast(__MODULE__, :stop)
  end
  
  # GenServer Callbacks
  @impl true
  def init(_args) do
    {:ok, %{running: false}}
  end
  
  @impl true
  def handle_cast(:start_interactive, state) do
    IO.puts("Starting Engineering Analytics Terminal CLI...")
    display_welcome()
    main_menu()
    {:noreply, Map.put(state, :running, true)}
  end
  
  @impl true
  def handle_cast(:stop, state) do
    IO.puts("Stopping CLI...")
    {:stop, :normal, state}
  end
  
  # CLI Functions
  defp display_welcome do
    IO.puts("""
    ============================================
    Engineering Analytics Terminal - CLI
    BarentsWatch Data Analytics Platform
    ============================================
    """)
  end
  
  defp main_menu do
    IO.puts("""
    Main Menu:
    1. Test BarentsWatch API Connection
    2. List Available Endpoints
    3. Run Data Analysis Demo
    4. Exit
    """)
    
    IO.write("Select an option (1-4): ")
    
    case IO.gets("\n") |> String.trim() do
      "1" -> test_api_connection()
      "2" -> list_endpoints()
      "3" -> run_analysis_demo()
      "4" -> exit_cli()
      _ -> 
        IO.puts("Invalid option, please try again.")
        main_menu()
    end
  end
  
  defp test_api_connection do
    IO.puts("Testing BarentsWatch API connection...")
    
    case Client.get("status") do
      {:ok, data} -> 
        IO.puts("✓ API connection successful!")
        IO.inspect(data, limit: 5)
      {:error, reason} -> 
        IO.puts("✗ API connection failed: #{reason}")
    end
    
    main_menu()
  end
  
  defp list_endpoints do
    endpoints = Client.list_endpoints()
    
    IO.puts("Available BarentsWatch API Endpoints:")
    Enum.each(endpoints, fn {endpoint, description} ->
      IO.puts("  • #{endpoint}: #{description}")
    end)
    
    main_menu()
  end
  
  defp run_analysis_demo do
    IO.puts("Running data analysis demo...")
    
    # Demo: Generate some sample data and analyze it
    sample_data = [1.2, 3.4, 5.6, 2.1, 4.5, 6.7, 3.2, 4.8]
    
    case EngineeringAnalyticsTerminal.Analytics.analyze(sample_data, :descriptive) do
      {:ok, stats} ->
        IO.puts("Analysis Results:")
        IO.inspect(stats)
      {:error, reason} ->
        IO.puts("Analysis failed: #{reason}")
    end
    
    main_menu()
  end
  
  defp exit_cli do
    IO.puts("Thank you for using Engineering Analytics Terminal!")
    :init.stop()
  end
end