# Development environment configuration

use Mix.Config

# Development specific logging
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug

# Development API configuration - use mock data for testing
config :endgate,
  api_client: [
    barentswatch: [
      # In development, we can use a shorter timeout for faster feedback
      timeout: 10_000,
      # Enable mock mode for development when API key is not available
      mock_mode: true,
      # Mock data file path
      mock_data_path: "priv/mock_data"
    ]
  ],
  
  # Development data processing - less strict validation
  data_processing: [
    validation_strict: false,
    cache_ttl: 600  # 10 minutes for faster testing
  ],
  
  # Development realtime - smaller limits for testing
  realtime: [
    max_clients: 10,
    message_history: 10
  ]

# Development database configuration (commented out until implemented)
# config :endgate, Endgate.Repo,
#   database: "endgate_dev",
#   show_sensitive_data_on_connection_error: true,
#   pool_size: 10