defmodule BrandoMCP.Embedded do
  @moduledoc """
  In-process tool calls, with no transport.

  A host that has already authenticated a user calls a tool as a plain
  function call. Nothing listens, and nothing is mounted.

      BrandoMCP.Embedded.call_tool("brando_content_search_entries", %{"query" => "Sommerro"}, user,
        conversation_id: id, attachments: %{"image1" => %{kind: :image, id: 12, label: "lobby.jpg"}})

  The actor comes from the host, never from the arguments.

  `:origin` and `:client` say where a proposal comes from (e.g.
  `origin: :mcp, client: "Claude Code"`), for Brando's review screen. Leave
  them out for the admin's own agent.
  """

  @doc """
  Call MCP tool `name` with `args` as `actor`. Returns the MCP tool result;
  a failed tool call has `isError: true`.
  """
  def call_tool(name, args, actor, opts \\ []) when not is_nil(actor) do
    state = %{
      brando_actor: actor,
      brando_origin: opts[:origin],
      brando_client: opts[:client],
      brando_conversation_id: opts[:conversation_id],
      brando_proposal_id: opts[:proposal_id],
      brando_attachments: opts[:attachments] || %{}
    }

    {:ok, result, _state} = BrandoMCP.Server.handle_call_tool(name, args || %{}, state)
    {:ok, result}
  end

  @doc "The MCP tool list, for hosts that want the same catalogue in-process."
  def list_tools do
    {:ok, tools, _cursor, _state} = BrandoMCP.Server.handle_list_tools(nil, %{})
    tools
  end
end
