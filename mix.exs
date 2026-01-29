defmodule EngineeringAnalyticsTerminal.MixProject do
  use Mix.Project

  def project do
    [
      app: :engineering_analytics_terminal,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EngineeringAnalyticsTerminal.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.0"},      # HTTP client for API requests
      {:jason, "~> 1.4"},           # JSON parser
      {:poison, "~> 5.0"},          # Alternative JSON library
      {:tesla, "~> 1.7"},           # HTTP client with middleware support
      {:req, "~> 0.4"},             # Modern HTTP client
      {:table_rex, "~> 3.1"},      # For tabular data display
      {:nimble_csv, "~> 1.2"}      # For CSV data handling
    ]
  end
end
