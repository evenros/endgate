# Engineering Analytics Terminal

A terminal-based application for accessing and analyzing BarentsWatch data through a command-line interface. This Elixir application provides interactive access to maritime and environmental data analytics.

## Features

- **BarentsWatch API Integration**: Connect to the BarentsWatch API for maritime data
- **Interactive CLI**: User-friendly command-line interface with menu navigation
- **Data Analytics**: Built-in analytics capabilities for data processing
- **Modular Architecture**: Supervised application with separate components for API, analytics, and CLI

## Installation

### Prerequisites

- Elixir 1.19+
- Erlang/OTP 25+
- Git

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/engineering_analytics_terminal.git
cd engineering_analytics_terminal

# Install dependencies
mix deps.get

# Compile the application
mix compile
```

### As a Dependency

If available in Hex, add to your `mix.exs`:

```elixir
def deps do
  [
    {:engineering_analytics_terminal, "~> 0.1.0"}
  ]
end
```

## Usage

### Starting the Application

```bash
# Start the interactive CLI
mix run --no-halt

# Or start in interactive Elixir shell
iex -S mix
EngineeringAnalyticsTerminal.CLI.start_interactive()
```

### CLI Menu Options

1. **Test BarentsWatch API Connection** - Verify connectivity to the BarentsWatch API
2. **List Available Endpoints** - Display all available API endpoints and their descriptions
3. **Run Data Analysis Demo** - Execute a sample data analysis demonstration
4. **Exit** - Quit the application

### Example Workflow

```
============================================
Engineering Analytics Terminal - CLI
BarentsWatch Data Analytics Platform
============================================

Main Menu:
1. Test BarentsWatch API Connection
2. List Available Endpoints
3. Run Data Analysis Demo
4. Exit

Select an option (1-4): 1

Testing BarentsWatch API connection...
✓ API connection successful!
%{status: "ok", timestamp: "2024-01-29T10:00:00Z"}
```

## Architecture

The application follows a supervised architecture with these main components:

- **BarentsWatch Client**: Handles API communication with BarentsWatch services
- **Data Processing**: Processes and transforms incoming data
- **Analytics Engine**: Performs statistical analysis on datasets
- **CLI Interface**: Provides interactive user interface

### Supervision Tree

```
EngineeringAnalyticsTerminal.Supervisor
├── BarentsWatch.Supervisor
├── DataProcessing.Supervisor
├── Analytics.Supervisor
└── CLI.Supervisor
```

## Configuration

Configure API endpoints and settings in your `config/config.exs`:

```elixir
config :engineering_analytics_terminal,
  barentswatch_api_url: "https://api.barentswatch.no",
  timeout: 30_000,
  max_retries: 3
```

## Development

### Running Tests

```bash
mix test
```

### Formatting Code

```bash
mix format
```

### Interactive Shell

```bash
iex -S mix
```

## Dependencies

- **HTTP Clients**: `httpoison`, `tesla`, `req` for API communication
- **JSON Processing**: `jason`, `poison` for data parsing
- **Data Display**: `table_rex` for tabular data presentation
- **CSV Handling**: `nimble_csv` for CSV data processing

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please open issues and pull requests on GitHub.

## Support

For questions or issues, please contact the maintainers or open a GitHub issue.
