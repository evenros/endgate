defmodule EngineeringAnalyticsTerminal.Analytics do
  @moduledoc """
  Analytics engine using functional programming paradigms.
  
  This module provides pure functions for statistical analysis,
  pattern detection, and predictive analytics.
  """
  
  @doc """
  Performs statistical analysis on dataset.
  
  ## Parameters
    - data: Dataset to analyze (list of numbers or list of maps)
    - analysis_type: Type of analysis as atom
  
  ## Returns
    - {:ok, analysis_results} on success
    - {:error, reason} on failure
  """
  def analyze(data, analysis_type) when is_list(data) do
    case analysis_type do
      :descriptive -> descriptive_statistics(data)
      :correlation -> {:ok, correlation_analysis(data)}
      :regression -> {:ok, regression_analysis(data)}
      :trend -> {:ok, trend_analysis(data)}
      :anomaly -> {:ok, anomaly_detection(data)}
      _ -> {:error, "Unknown analysis type: #{inspect(analysis_type)}"}
    end
  end
  
  def analyze(_data, _analysis_type) do
    {:error, "Invalid data format: expected list"}
  end
  
  @doc """
  Generates insights from data based on context.
  
  ## Parameters
    - data: Dataset to analyze
    - context: Analysis context as atom
  
  ## Returns
    - {:ok, insights} on success
    - {:error, reason} on failure
  """
  def generate_insights(data, context) when is_map(data) or is_list(data) do
    case context do
      :maritime_safety -> {:ok, maritime_safety_insights(data)}
      :weather_forecasting -> {:ok, weather_forecasting_insights(data)}
      :traffic_analysis -> {:ok, traffic_analysis_insights(data)}
      :environmental_monitoring -> {:ok, environmental_insights(data)}
      _ -> {:error, "Unknown context: #{inspect(context)}"}
    end
  end
  
  def generate_insights(_data, _context) do
    {:error, "Invalid data format: expected map or list"}
  end
  
  # Private functions using pattern matching
  defp descriptive_statistics(data) when is_list(data) and length(data) > 0 do
    values = extract_numeric_values(data)
    
    case values do
      [] -> {:error, "No numeric values found in data"}
      _ -> 
        {:ok, %{
          count: length(values),
          mean: calculate_mean(values),
          median: calculate_median(values),
          std_dev: calculate_std_dev(values),
          min: Enum.min(values),
          max: Enum.max(values),
          quartiles: calculate_quartiles(values)
        }}
    end
  end
  
  defp descriptive_statistics(_data) do
    {:error, "Invalid data for descriptive statistics"}
  end
  
  # Helper functions with pattern matching
  defp extract_numeric_values([]), do: []
  defp extract_numeric_values([head | tail]) when is_number(head), do: [head | extract_numeric_values(tail)]
  defp extract_numeric_values([_head | tail]), do: extract_numeric_values(tail)
  
  defp calculate_mean(values), do: Enum.sum(values) / length(values)
  defp calculate_median(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    
    case rem(len, 2) do
      0 -> (Enum.at(sorted, div(len, 2) - 1) + Enum.at(sorted, div(len, 2))) / 2
      _ -> Enum.at(sorted, div(len, 2))
    end
  end
  
  defp calculate_std_dev(values) do
    mean = calculate_mean(values)
    squared_diffs = Enum.map(values, &(&1 - mean))
    variance = Enum.sum(squared_diffs) / length(values)
    :math.sqrt(variance)
  end
  
  defp calculate_quartiles(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    
    q1_index = div(len, 4)
    q2_index = div(len, 2)
    q3_index = div(3 * len, 4)
    
    [
      Enum.at(sorted, q1_index),
      Enum.at(sorted, q2_index),
      Enum.at(sorted, q3_index)
    ]
  end
  
  # Placeholder functions for other analysis types
  defp correlation_analysis(_data), do: %{
    correlations: [],
    significant_correlations: []
  }
  
  defp regression_analysis(_data), do: %{
    model: "linear_regression",
    coefficients: [],
    r_squared: 0.0,
    p_values: []
  }
  
  defp trend_analysis(_data), do: %{
    trends: [],
    trend_strength: 0.0,
    trend_direction: "stable"
  }
  
  defp anomaly_detection(_data), do: %{
    anomalies: [],
    anomaly_score: 0.0
  }
  
  # Context-specific insight generators
  defp maritime_safety_insights(_data), do: %{
    safety_alerts: [],
    risk_assessment: "low",
    recommendations: []
  }
  
  defp weather_forecasting_insights(_data), do: %{
    weather_patterns: [],
    severe_weather_risk: "low",
    recommendations: []
  }
  
  defp traffic_analysis_insights(_data), do: %{
    traffic_patterns: [],
    congestion_level: "low",
    recommendations: []
  }
  
  defp environmental_insights(_data), do: %{
    environmental_trends: [],
    risk_level: "low",
    recommendations: []
  }
end