defmodule EngineeringAnalyticsTerminal.BarentsWatch.Client do
  @moduledoc """
  BarentsWatch API Client using GenServer for stateful HTTP connections.
  
  This module handles all HTTP communication with BarentsWatch APIs,
  manages connection pooling, and provides a clean interface for API requests.
  """
  
  use GenServer
  
  # Client API
  @doc """
  Starts the BarentsWatch API client.
  
  ## Parameters
    - opts: Options for the client (e.g., timeout, retries)
  
  ## Returns
    - {:ok, pid} on success
    - {:error, reason} on failure
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_link do
    start_link([])
  end
  
  @doc """
  Makes a GET request to a BarentsWatch API endpoint.
  
  ## Parameters
    - endpoint: The API endpoint to call
    - params: Query parameters as keyword list
    - headers: Additional HTTP headers
  
  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def get(endpoint, params, headers) when is_binary(endpoint) and is_list(params) and is_list(headers) do
    GenServer.call(__MODULE__, {:get, endpoint, params, headers})
  end
  
  def get(endpoint, params) when is_binary(endpoint) and is_list(params) do
    get(endpoint, params, [])
  end
  
  def get(endpoint) when is_binary(endpoint) do
    get(endpoint, [], [])
  end
  
  @doc """
  Makes a POST request to a BarentsWatch API endpoint.
  
  ## Parameters
    - endpoint: The API endpoint to call
    - body: Request body as map
    - headers: Additional HTTP headers
  
  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def post(endpoint, body, headers) when is_binary(endpoint) and is_map(body) and is_list(headers) do
    GenServer.call(__MODULE__, {:post, endpoint, body, headers})
  end
  
  def post(endpoint, body) when is_binary(endpoint) and is_map(body) do
    post(endpoint, body, [])
  end
  
  @doc """
  Lists all available BarentsWatch API endpoints.
  
  ## Returns
    - Map of available endpoints with descriptions
  """
  def list_endpoints do
    endpoints()
  end
  
  @doc """
  Gets endpoint description.
  
  ## Parameters
    - endpoint: Endpoint name as binary
  
  ## Returns
    - Description as binary or nil if not found
  """
  def get_endpoint_description(endpoint) when is_binary(endpoint) do
    endpoints()[endpoint]
  end
  
  defp endpoints do
    %{
      "weather/current" => "Current weather data",
      "weather/forecast" => "Weather forecast data",
      "weather/historical" => "Historical weather data",
      "weather/alerts" => "Weather alerts and warnings",
      "ais/current" => "Current vessel positions",
      "ais/vessels" => "Vessel details",
      "ais/search" => "Vessel search",
      "ais/density" => "Vessel traffic density",
      "ocean/current" => "Current oceanographic data",
      "ocean/forecast" => "Ocean forecast data",
      "ice/current" => "Current sea ice data",
      "ice/forecast" => "Sea ice forecast data"
    }
  end
  
  # GenServer Callbacks
  @impl true
  def init(opts) do
    state = %{
      base_url: "https://api.barentswatch.no",
      timeout: Keyword.get(opts, :timeout, 10_000),
      retries: Keyword.get(opts, :retries, 3),
      headers: [
        "Accept": "application/json",
        "Content-Type": "application/json"
      ]
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get, endpoint, params, headers}, _from, state) do
    url = build_url(state.base_url, endpoint, params)
    merged_headers = state.headers ++ headers
    
    make_request(:get, url, merged_headers, state)
  end
  
  @impl true
  def handle_call({:post, endpoint, body, headers}, _from, state) do
    url = "#{state.base_url}/#{endpoint}"
    merged_headers = state.headers ++ headers
    
    make_request(:post, url, merged_headers, state, body)
  end
  
  # Private functions
  defp build_url(base_url, endpoint, params) do
    query_string =
      case params do
        [] -> ""
        _ -> "?" <> URI.encode_query(params)
      end
    
    "#{base_url}/#{endpoint}#{query_string}"
  end
  
  defp make_request(method, url, headers, state) do
    make_request(method, url, headers, state, nil)
  end
  
  defp make_request(:get, url, headers, state, _body) do
    case HTTPoison.get(url, headers, timeout: state.timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        decode_response(body)
      
      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "API request failed with status #{status_code}: #{body}"}
      
      {:error, reason} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end
  
  defp make_request(:post, url, headers, state, body) do
    case HTTPoison.post(url, Jason.encode!(body), headers, timeout: state.timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        decode_response(body)
      
      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "API request failed with status #{status_code}: #{body}"}
      
      {:error, reason} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end
  
  defp decode_response(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "JSON decode failed: #{reason}"}
    end
  end
  
  # Available endpoints
  @endpoints %{
    "weather/current" => "Current weather data",
    "weather/forecast" => "Weather forecast data",
    "weather/historical" => "Historical weather data",
    "weather/alerts" => "Weather alerts and warnings",
    "ais/current" => "Current vessel positions",
    "ais/vessels" => "Vessel details",
    "ais/search" => "Vessel search",
    "ais/density" => "Vessel traffic density",
    "ocean/current" => "Current oceanographic data",
    "ocean/forecast" => "Ocean forecast data",
    "ice/current" => "Current sea ice data",
    "ice/forecast" => "Sea ice forecast data"
  }
end