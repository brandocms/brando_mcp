defmodule BrandoMCP.Config do
  @moduledoc """
  Runtime configuration for BrandoMCP.

  Configuration is read from the host application's `:brando_mcp`
  environment. Keeping it runtime-based lets one release use different
  safety policies in development and production.
  """

  @default_page_size 25
  @max_page_size 100
  @serializer_depth 3
  @max_seed_batch_size 50

  def adapter, do: get(:adapter, BrandoMCP.Brando)
  def blueprints, do: get(:blueprints)
  def include_brando_blueprints?, do: get(:include_brando_blueprints, false)
  def default_page_size, do: get(:default_page_size, @default_page_size)
  def max_page_size, do: get(:max_page_size, @max_page_size)
  def max_seed_batch_size, do: get(:max_seed_batch_size, @max_seed_batch_size)
  def serializer_depth, do: get(:serializer_depth, @serializer_depth)

  def translation_content_adapter,
    do: get(:translation_content_adapter, Module.concat(["Brando", "AI", "Translation"]))

  def repo, do: get(:repo, Module.concat(["Brando", "Repo"]))
  def user, do: get(:user)
  def user_resolver, do: get(:user_resolver)
  def writable_blueprints, do: get(:writable_blueprints, :all)

  def writes_enabled? do
    get(:writes_enabled, false) || truthy_env?(System.get_env("BRANDO_MCP_WRITES_ENABLED"))
  end

  def get(key, default \\ nil) do
    Application.get_env(:brando_mcp, key, default)
  end

  defp truthy_env?(value), do: value in ["1", "true", "TRUE", "yes", "YES"]
end
