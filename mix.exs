defmodule Endgate.MixProject do
  use Mix.Project

  def project do
    [
      app: :endgate,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: {Endgate.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib", "apps/*/lib"]

  # Specifies your project dependencies
  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.5"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:poison, "~> 5.0"},
      
      # Phoenix web framework (will be added when we create the web app)
      # {:phoenix, "~> 1.7"},
      # {:phoenix_live_view, "~> 0.18"},
      # {:phoenix_html, "~> 3.3"},
      
      # Background job processing
      {:oban, "~> 2.15"},
      
      # Data processing and analytics
      {:stream_data, "~> 0.5"},
      {:table_rex, "~> 3.1"},
      
      # CLI interface
      {:table_rex, "~> 3.1"},
      {:nimble_options, "~> 1.0"},
      
      # Testing
      {:ex_machina, "~> 2.7", only: :test}
    ]
  end

  # Defines aliases for common tasks
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end