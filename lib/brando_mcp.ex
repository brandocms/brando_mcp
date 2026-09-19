defmodule BrandoMCP do
  @moduledoc """
  Model Context Protocol endpoint for Brando CMS applications.

  Mount BrandoMCP in the host application's Phoenix endpoint, before
  `Plug.Parsers`:

      if Code.ensure_loaded?(BrandoMCP) do
        plug BrandoMCP
      end

  This serves Streamable HTTP on `/brando/mcp` using the Phoenix endpoint's
  existing web server. No additional listener or port is started.
  """

  @behaviour Plug

  import Plug.Conn

  @default_path "/brando/mcp"
  @server_info %{name: "brando", version: "0.1.0"}

  @impl Plug
  def init(opts) do
    path = opts |> Keyword.get(:at, @default_path) |> path_segments!()

    http_opts =
      opts
      |> Keyword.drop([:allow_remote_access, :at])
      |> Keyword.put(:handler, BrandoMCP.Server)
      |> Keyword.put_new(:server_info, @server_info)
      |> ExMCP.HttpPlug.init()

    %{
      allow_remote_access: Keyword.get(opts, :allow_remote_access, false),
      http_opts: http_opts,
      path: path
    }
  end

  @impl Plug
  def call(conn, config) do
    case Enum.split(conn.path_info, length(config.path)) do
      {path, rest} when path == config.path ->
        conn
        |> validate_mount_position!()
        |> authorize_connection(config)
        |> forward_if_authorized(rest, config.http_opts)
        |> halt()

      _other ->
        conn
    end
  end

  @doc "Starts the MCP server using the supplied transport options."
  def start_link(opts \\ []) do
    BrandoMCP.Server.start_link(opts)
  end

  defp path_segments!(path) when is_binary(path) do
    segments = String.split(path, "/", trim: true)

    if String.starts_with?(path, "/") and segments != [] do
      segments
    else
      raise ArgumentError, ":at must be an absolute, non-root path"
    end
  end

  defp path_segments!(path) do
    raise ArgumentError, ":at must be a string, got: #{inspect(path)}"
  end

  defp validate_mount_position!(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn), do: conn

  defp validate_mount_position!(_conn) do
    raise """
    plug BrandoMCP is running after the request body has been parsed.
    Mount it before Plug.Parsers in your Phoenix endpoint.
    """
  end

  defp authorize_connection(conn, %{allow_remote_access: true}), do: conn

  defp authorize_connection(conn, _config) do
    cond do
      not local?(conn.remote_ip) ->
        forbidden(conn, """
        BrandoMCP does not accept remote connections by default.

        To deliberately expose it, mount the plug with `allow_remote_access: true`.
        """)

      get_req_header(conn, "origin") != [] ->
        forbidden(conn, """
        BrandoMCP does not accept requests with an Origin header by default.
        """)

      true ->
        conn
    end
  end

  defp forward_if_authorized(%Plug.Conn{halted: true} = conn, _rest, _opts), do: conn

  defp forward_if_authorized(conn, rest, opts) do
    Plug.forward(conn, rest, ExMCP.HttpPlug, opts)
  end

  defp local?({127, _second, _third, _fourth}), do: true
  defp local?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  defp local?({0, 0, 0, 0, 0, 65_535, first, _second})
       when first in 32_512..32_767,
       do: true

  defp local?(_remote_ip), do: false

  defp forbidden(conn, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(403, message)
    |> halt()
  end
end
