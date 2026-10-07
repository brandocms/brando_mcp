defmodule BrandoMCP.Content do
  @moduledoc """
  Brando's content-proposal tools, exposed through MCP.

  The tools, and their descriptions and parameters, come from the host's
  `Brando.Content.Proposals.Tools` registry: the same set the Brando admin's
  content agent uses, each named here with a `brando_content_` prefix. They
  read content and prepare proposals for a user to review in the Brando admin.
  No tool approves or applies anything.

  They run only for the authenticated actor in the MCP handler state
  (`:brando_actor`), which the host sets: `BrandoMCP.Embedded.call_tool/4` and
  `mix brando.mcp` do. Nothing in a tool call's arguments can choose the user.
  """
  alias BrandoMCP.{Config, Result}

  @prefix "brando_content_"

  # Tools that change nothing. The rest — `prepare_proposal`, which stores a
  # proposal for review, `attach_folder`, which attaches media to an admin
  # conversation, and any tool added to Brando later — are not read-only.
  @reads ~w(list_content_types describe_content_type search_entries entry_outline list_modules
            describe_module request_media look_at_media list_entry_media list_selection_options
            list_attachments search_assets find_media_folders)

  @doc "The MCP tool definitions; empty when this Brando version has no content tools."
  def tools do
    if available?(), do: Enum.map(Config.content_tools().definitions(), &tool/1), else: []
  end

  @doc "Whether the host's Brando has the content-proposal tool registry."
  def available? do
    registry = Config.content_tools()
    Code.ensure_loaded?(registry) and function_exported?(registry, :definitions, 0)
  end

  @doc """
  Call MCP tool `name` for the actor in `state`. Returns the MCP result and the
  state; a stored proposal becomes the one the next `prepare_proposal` refines.
  """
  def call(@prefix <> name, args, state) do
    cond do
      not available?() ->
        {:ok, Result.error("This Brando version has no content proposal tools."), state}

      is_nil(actor(state)) ->
        {:ok,
         Result.error(
           "Content tools need an authenticated Brando actor from the host. They are not available to anonymous callers."
         ), state}

      true ->
        run(name, args, state)
    end
  end

  def call(name, _args, state), do: {:ok, Result.error("Unknown tool: #{name}"), state}

  @doc false
  def actor(state), do: state_value(state, :brando_actor)

  defp run(name, args, state) do
    registry = Config.content_tools()

    context =
      struct(Module.concat(registry, "Context"),
        actor: actor(state),
        conversation_id: state_value(state, :brando_conversation_id),
        proposal_id: state_value(state, :brando_proposal_id),
        attachments: state_value(state, :brando_attachments) || %{}
      )

    case registry.call(name, stringify(args), context) do
      {:ok, %{proposal_id: id} = data} when name == "prepare_proposal" ->
        {:ok, Result.ok(data), Map.put(state, :brando_proposal_id, id)}

      {:ok, data} ->
        {:ok, Result.ok(data), state}

      {:error, reason} ->
        {:ok, Result.error(reason), state}
    end
  rescue
    exception -> {:ok, Result.error(Exception.message(exception)), state}
  end

  defp tool(%{name: name} = definition) do
    %{
      name: @prefix <> name,
      description: definition.description,
      inputSchema: definition.parameters,
      annotations: %{
        readOnlyHint: name in @reads,
        destructiveHint: false,
        openWorldHint: false
      }
    }
  end

  defp state_value(state, key) when is_map(state), do: Map.get(state, key)
  defp state_value(_, _), do: nil

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_), do: %{}
end
