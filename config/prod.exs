# Production environment configuration

use Mix.Config

# Production logging - more structured
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

# Production API configuration - optimize for performance
config :endgate,
  api_client: [
    barentswatch: [
      # Increase timeout for production
      timeout: 60_000,
      # Larger connection pool for production
      pool_size: 20,
      pool_max_overflow: 10,
      # Disable mock mode in production
      mock_mode: false
    ]
  ],
  
  # Production data processing - optimize for performance
  data_processing: [
    batch_size: 5000,
    max_concurrency: 10,
    cache_ttl: 7200  # 2 hours
  ],
  
  # Production realtime - scale for more clients
  realtime: [
    max_clients: 5000,
    message_history: 500
  ],
  
  # Production workers - more capacity
  workers: [
    max_jobs: 500,
    job_timeout: 7200  # 2 hours
  ]

# Production database configuration (commented out until implemented)
# config :endgate, Endgate.Repo,
#   pool_size: 20,
#   timeout: 15_000,
#   queue_target: 5_000,
#   queue_interval: 5_000

# Enable SSL in production
config :endgate, Endgate.Endpoint,
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  https: [
    port: String.to_integer(System.get_env("HTTPS_PORT") || "443"),
    otp_app: :endgate,
    cipher_suite: :strong,
    keyfile: System.get_env("SSL_KEYFILE"),
    certfile: System.get_env("SSL_CERTFILE"),
    transport_options: [socket_opts: [:inet6]]
  ],
  url: [host: System.get_env("HOST") || "localhost", port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Configure Oban for production
config :endgate, Oban,
  plugins: [Oban.Plugins.Pruner, Oban.Plugins.Lifeline, Oban.Plugins.Cron],
  queues: [default: 20, events: 10],
  repo: Endgate.Repo