defmodule EngineeringAnalyticsTerminal do
  @moduledoc """
  Main module for the Engineering Analytics Terminal.
  
  This application provides a comprehensive data analytics platform
  for consuming and analyzing BarentsWatch API data in real-time.
  """
  
  @doc """
  Starts the Engineering Analytics Terminal application.
  
  This function starts the main application supervisor which manages
  all the child processes including API clients, data processors, and analytics engines.
  """
  def start do
    EngineeringAnalyticsTerminal.Application.start(:normal, [])
  end
  
  @doc """
  Provides a quick overview of available functionality.
  """
  def help do
    IO.puts("""
    Engineering Analytics Terminal - BarentsWatch Data Platform
    
    Available Modules:
    - BarentsWatch API Client: Access to all BarentsWatch APIs
    - Weather Data: Real-time and historical weather information  
    - AIS Data: Vessel tracking and maritime traffic analysis
    - Data Processing: Data transformation and normalization
    - Analytics Engine: Advanced data analysis and insights
    - Real-time Streaming: Live data feeds and updates
    - CLI Interface: Interactive command-line interface
    
    Usage:
    - Start the application: EngineeringAnalyticsTerminal.start()
    - Access specific APIs through their respective modules
    - Use the CLI for interactive data exploration
    """)
  end
  
  @doc """
  Gets version information.
  """
  def version do
    "Engineering Analytics Terminal v0.1.0 - BarentsWatch API Integration"
  end
end