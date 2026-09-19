defmodule BrandoMCP.Adapter do
  @moduledoc """
  Boundary between MCP tools and a running Brando application.

  The default implementation is `BrandoMCP.Brando`. Applications can replace
  it for tenancy, authorization, or remote execution.
  """

  @callback system_info() :: {:ok, map()} | {:error, term()}
  @callback list_blueprints(map()) :: {:ok, map()} | {:error, term()}
  @callback describe_blueprint(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_entries(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_entry(String.t(), integer() | String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback create_entry(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_entry(String.t(), integer() | String.t(), map(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_entry(String.t(), integer() | String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback seed_contract(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback validate_seed_batch(String.t(), [map()], map()) ::
              {:ok, map()} | {:error, term()}
  @callback apply_seed_batch(String.t(), [map()], map()) ::
              {:ok, map()} | {:error, term()}
  @callback prepare_translation(String.t(), integer() | String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback validate_translation(String.t(), integer() | String.t(), [map()], map()) ::
              {:ok, map()} | {:error, term()}
  @callback apply_translation(String.t(), integer() | String.t(), [map()], map()) ::
              {:ok, map()} | {:error, term()}
end
