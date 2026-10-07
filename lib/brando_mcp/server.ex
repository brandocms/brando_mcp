defmodule BrandoMCP.Server do
  @moduledoc """
  The MCP handler: Brando's content-proposal tools (see `BrandoMCP.Content`)
  for one authenticated actor.

  The actor comes from `start_link/1`'s `:actor` option, set by
  `mix brando.mcp` to the configured local user, and never from the MCP
  client. Without an actor every tool call is refused.

  The only transport is stdio. There is no HTTP or other network transport.
  """
  use ExMCP.Server.Handler

  alias BrandoMCP.Content
  alias ExMCP.Internal.VersionRegistry

  @server_info %{"name" => "brando", "version" => Mix.Project.config()[:version]}

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc """
  Serve MCP over this process's standard input and output as `opts[:actor]`.
  The server stops when standard input closes.
  """
  def start_link(opts) do
    ExMCP.Server.StdioServer.start_link(Keyword.put(opts, :module, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       brando_actor: opts[:actor],
       brando_origin: :mcp,
       brando_client: nil,
       brando_conversation_id: nil,
       brando_proposal_id: nil,
       brando_attachments: %{}
     }}
  end

  @impl ExMCP.Server.Handler
  def handle_initialize(params, state) do
    requested = params["protocolVersion"] || VersionRegistry.latest_version()

    version =
      case VersionRegistry.negotiate_version(requested, VersionRegistry.supported_versions()) do
        {:ok, version} -> version
        {:error, _} -> VersionRegistry.latest_version()
      end

    {:ok,
     %{
       "protocolVersion" => version,
       "serverInfo" => @server_info,
       "capabilities" => %{"tools" => %{}}
     }, Map.put(state, :brando_client, client_name(params["clientInfo"]))}
  end

  # The connecting tool's name, for the admin's review screen ("From Claude
  # Code via MCP"). Clients send a slug as `name` and a display `title`.
  defp client_name(%{} = info) do
    case info["title"] || info["name"] do
      name when is_binary(name) ->
        name
        |> String.split(["\n", "\r"], parts: 2)
        |> hd()
        |> String.trim()
        |> String.slice(0, 80)
        |> case do
          "" -> nil
          name -> name
        end

      _ ->
        nil
    end
  end

  defp client_name(_info), do: nil

  @impl ExMCP.Server.Handler
  def handle_list_tools(_cursor, state), do: {:ok, Content.tools(), nil, state}

  @impl ExMCP.Server.Handler
  def handle_call_tool(name, arguments, state) do
    Content.call(name, Map.delete(arguments || %{}, "_meta"), state)
  end

  # ExMCP's stdio server hands every other method to this function.
  # Notifications get no response; `ping` gets an empty one.
  def handle_request("notifications/" <> _, _params, state), do: {:noreply, state}
  def handle_request("ping", _params, state), do: {:reply, %{}, state}

  def handle_request(method, _params, state),
    do: {:error, "Method not found: #{method}", state}
end
