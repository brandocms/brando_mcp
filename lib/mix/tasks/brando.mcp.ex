defmodule Mix.Tasks.Brando.Mcp do
  use Mix.Task

  @shortdoc "Serves Brando's content tools over stdio to a local coding agent (dev only)"

  @moduledoc """
  Serves Brando's content-proposal tools over MCP stdio, for a local coding
  agent such as Claude Code, as a named Brando user.

      mix brando.mcp --user dev@example.com

  The user can also be configured, and `--user` overrides it:

      # config/dev.exs
      config :brando_mcp, user: "dev@example.com"

  Every tool call carries that user's own permissions. The tools read content
  and prepare proposals; approving and applying them happens in the Brando
  admin.

  This is a development tool. It refuses to start with `MIX_ENV=prod` or
  inside a release, and it has no network transport.
  """

  @switches [user: :string, transport: :string]

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if remaining != [] or invalid != [] do
      Mix.raise("Invalid arguments: #{inspect(remaining ++ invalid)}")
    end

    ensure_stdio!(opts[:transport])

    with {:error, message} <- BrandoMCP.Stdio.ensure_dev(), do: Mix.raise(message)

    configure_stdio_logging()
    # Standard output carries only JSON-RPC messages: keep compiler output off it.
    Mix.shell(Mix.Shell.Quiet)
    Mix.Task.run("app.start")

    case BrandoMCP.Stdio.start(opts[:user] || BrandoMCP.Config.user()) do
      {:ok, pid, user} ->
        announce(user)
        await(pid)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp ensure_stdio!(nil), do: :ok
  defp ensure_stdio!("stdio"), do: :ok

  defp ensure_stdio!(transport) do
    Mix.raise("""
    mix brando.mcp serves stdio only; --transport #{transport} is not available.

    BrandoMCP has no HTTP or other network transport.
    """)
  end

  defp await(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      {:DOWN, ^ref, :process, ^pid, reason} -> Mix.raise("BrandoMCP stopped: #{inspect(reason)}")
    end
  end

  # Standard output carries only JSON-RPC messages, so this goes to stderr.
  defp announce(user) do
    role = if Map.get(user, :role) == :superuser, do: " (a superuser)", else: ""
    IO.puts(:stderr, "BrandoMCP: serving stdio as #{user.email}#{role}.")
  end

  defp configure_stdio_logging do
    Application.put_env(:ex_mcp, :stdio_mode, true)
    Application.put_env(:logger, :level, :emergency)
    Logger.configure(level: :emergency)
    :logger.set_primary_config(:level, :emergency)
  end
end
