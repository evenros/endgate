# Test environment configuration

use Mix.Config

# Test logging - minimal
config :logger, :console,
  level: :warn

# Test API configuration - use mock data
config :endgate,
  api_client: [
    barentswatch: [
      # Always use mock mode in tests
      mock_mode: true,
      # Shorter timeouts for tests
      timeout: 5_000,
      max_retries: 1,
      retry_delay: 100
    ]
  ],
  
  # Test data processing - fast processing
  data_processing: [
    batch_size: 100,
    max_concurrency: 2,
    cache_ttl: 60  # 1 minute
  ],
  
  # Test realtime - minimal settings
  realtime: [
    max_clients: 5,
    message_history: 5
  ]

# Test database configuration
config :endgate, Endgate.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "test/endgate_test.db",
  pool_size: 2

# Configure Oban for testing
config :endgate, Oban,
  repo: Endgate.Repo,
  queues: [default: 2],
  plugins: [Oban.Plugins.Pruner]