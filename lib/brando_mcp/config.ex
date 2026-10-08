defmodule BrandoMCP.Config do
  @moduledoc """
  Runtime configuration for BrandoMCP, read from the host application's
  `:brando_mcp` environment.

      # config/dev.exs
      config :brando_mcp, user: "dev@example.com"

  `:user` is the email of the Brando user that `mix brando.mcp` runs as.
  `--user` overrides it. There is no default user.
  """

  @doc "The email of the Brando user `mix brando.mcp` runs as, if configured."
  def user, do: get(:user)

  @doc false
  def content_tools,
    do: get(:content_tools, Module.concat(["Brando", "Content", "Proposals", "Tools"]))

  @doc false
  def users, do: get(:users, Module.concat(["Brando", "Users"]))

  @doc false
  def activity, do: get(:activity, Module.concat(["Brando", "Activity"]))

  @doc false
  def get(key, default \\ nil), do: Application.get_env(:brando_mcp, key, default)
end
