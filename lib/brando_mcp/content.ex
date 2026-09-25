defmodule BrandoMCP.Content do
  @moduledoc """
  Brando's content-proposal tools, exposed through MCP.

  The tools are defined in the host's `Brando.Content.Proposals.Tools`; this
  module only forwards to them. They read content and prepare proposals for a
  user to review in the Brando admin — no tool approves or applies.

  They run only for an authenticated actor that the host placed in the MCP
  handler state (`:brando_actor`), as `BrandoMCP.Embedded.call_tool/4` does.
  A `user_id` argument or the configured `:user` is never used for them, so a
  caller cannot choose whom it acts as.
  """
  alias BrandoMCP.{Config, Result}

  @doc "Call Brando content tool `name` for the actor in `state`."
  def call(name, args, state) do
    tools = Config.content_tools()
    context = Module.concat(tools, "Context")

    result =
      cond do
        not Code.ensure_loaded?(tools) ->
          {:error, "This Brando version has no content proposal tools."}

        is_nil(actor(state)) ->
          {:error,
           "Content tools need an authenticated Brando actor from the host. They are not available to anonymous callers."}

        true ->
          tools.call(
            name,
            stringify(args),
            struct(context,
              actor: actor(state),
              conversation_id: state_value(state, :brando_conversation_id),
              proposal_id: state_value(state, :brando_proposal_id),
              attachments: state_value(state, :brando_attachments) || %{}
            )
          )
      end

    case result do
      {:ok, data} -> {:ok, Result.ok(data), state}
      {:error, reason} -> {:ok, Result.error(reason), state}
    end
  end

  @doc false
  def actor(state), do: state_value(state, :brando_actor)

  defp state_value(state, key) when is_map(state), do: Map.get(state, key)
  defp state_value(_, _), do: nil

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_), do: %{}
end
