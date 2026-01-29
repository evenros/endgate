# Main configuration for Endgate Data Analytics Platform

use Mix.Config

# Application configuration
config :endgate,
  # API Client Configuration
  api_client: [
    # Barentswatch API configuration
    barentswatch: [
      base_url: System.get_env("BARENTWATCH_API_URL") || "https://api.barentswatch.no",
      api_key: System.get_env("BARENTWATCH_API_KEY"),
      timeout: 30_000,  # 30 seconds
      max_retries: 3,
      retry_delay: 1000,  # 1 second between retries
      pool_size: 10,
      pool_max_overflow: 5
    ]
  ],
  
  # Data Processing Configuration
  data_processing: [
    batch_size: 1000,
    max_concurrency: 5,
    cache_ttl: 3600,  # 1 hour in seconds
    validation_strict: true
  ],
  
  # Real-time Configuration
  realtime: [
    broadcast_interval: 1000,  # 1 second
    max_clients: 1000,
    message_history: 100,
    presence_timeout: 30000  # 30 seconds
  ],
  
  # Worker Configuration
  workers: [
    default_queue: :default,
    max_jobs: 100,
    job_timeout: 3600  # 1 hour
  ],
  
  # Logging Configuration
  logging: [
    level: String.to_atom(System.get_env("LOG_LEVEL") || "info"),
    file: "log/endgate.log",
    max_size: 10_000_000,  # 10MB
    rotation_count: 5
  ]

# Ecto Repository Configuration (will be implemented)
# config :endgate, Endgate.Repo,
#   adapter: Ecto.Adapters.Postgres,
#   database: System.get_env("DATABASE_NAME") || "endgate_dev",
#   username: System.get_env("DATABASE_USER") || "postgres",
#   password: System.get_env("DATABASE_PASSWORD") || "postgres",
#   hostname: System.get_env("DATABASE_HOST") || "localhost",
#   pool_size: 15

# Oban Configuration
config :endgate, Oban,
  repo: Endgate.Repo,
  queues: [default: 10],
  plugins: [Oban.Plugins.Pruner, Oban.Plugins.Lifeline],
  peer: [Oban.Peer.PG, Oban.Peer.Local],
  crontab: [
    # Example scheduled jobs
    # {"@daily", Endgate.Workers.DataSyncWorker}
  ]

# Import environment specific config
import_config "#{Mix.env()}.exs"