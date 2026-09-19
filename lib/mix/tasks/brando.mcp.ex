defmodule Mix.Tasks.Brando.Mcp do
  use Mix.Task

  @shortdoc "Starts an optional standalone BrandoMCP transport"

  @moduledoc """
  Starts a standalone BrandoMCP transport after booting the current Mix
  application.

      mix brando.mcp
      mix brando.mcp --transport http --port 4001 --host 127.0.0.1

  The default transport is `stdio`. Phoenix applications should normally mount
  `plug BrandoMCP` in their endpoint instead, so MCP shares the application's
  existing HTTP server.
  """

  @switches [
    transport: :string,
    port: :integer,
    host: :string,
    include_brando: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if remaining != [] or invalid != [] do
      Mix.raise("Invalid arguments: #{inspect(remaining ++ invalid)}")
    end

    transport = transport!(Keyword.get(opts, :transport, "stdio"))
    configure_stdio_logging(transport)
    Mix.Task.run("app.start")

    if Keyword.get(opts, :include_brando, false) do
      Application.put_env(:brando_mcp, :include_brando_blueprints, true)
    end

    server_opts =
      opts
      |> Keyword.take([:port, :host])
      |> Keyword.put(:transport, transport)

    case BrandoMCP.Server.start_link(server_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} ->
            :ok

          {:DOWN, ^ref, :process, ^pid, reason} ->
            Mix.raise("BrandoMCP stopped: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("Could not start BrandoMCP: #{inspect(reason)}")
    end
  end

  defp transport!("stdio"), do: :stdio
  defp transport!("http"), do: :http
  defp transport!("beam"), do: :beam
  defp transport!(transport), do: Mix.raise("Unsupported transport: #{transport}")

  defp configure_stdio_logging(:stdio) do
    Application.put_env(:ex_mcp, :stdio_mode, true)
    Application.put_env(:logger, :level, :emergency)
    Logger.configure(level: :emergency)
    :logger.set_primary_config(:level, :emergency)
  end

  defp configure_stdio_logging(_transport), do: :ok
end
