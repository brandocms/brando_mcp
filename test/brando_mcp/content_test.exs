defmodule BrandoMCP.ContentTest do
  use ExUnit.Case, async: false

  alias BrandoMCP.Test.FakeTools

  @actor %{id: 1, name: "Editor"}

  # Tools BrandoMCP used to expose that wrote content directly.
  @removed_writes ~w(brando_create_entry brando_update_entry brando_delete_entry
                     brando_apply_seed_batch brando_apply_translation)

  setup do
    BrandoMCP.Test.Env.setup(user: "dev@example.com", writes_enabled: true)
  end

  test "the tool list is Brando's content tool registry, prefixed" do
    names = Enum.map(BrandoMCP.Embedded.list_tools(), & &1.name)
    assert names == Enum.map(FakeTools.names(), &"brando_content_#{&1}")
  end

  test "registry definitions become MCP tools with safety annotations" do
    tools = Map.new(BrandoMCP.Embedded.list_tools(), &{&1.name, &1})

    assert %{
             description: "Fake search_entries.",
             inputSchema: %{type: "object", properties: %{query: _}},
             annotations: %{readOnlyHint: true, destructiveHint: false}
           } = tools["brando_content_search_entries"]

    for name <- ~w(brando_content_prepare_proposal brando_content_attach_folder) do
      assert %{readOnlyHint: false, destructiveHint: false} = tools[name].annotations
    end

    refute Enum.any?(Map.values(tools), & &1.annotations.destructiveHint)
  end

  test "no tool writes content directly, even with the old writes switch on" do
    names = Enum.map(BrandoMCP.Embedded.list_tools(), & &1.name)
    refute Enum.any?(names, &(&1 in @removed_writes))
    refute Enum.any?(names, &(&1 =~ ~r/apply|approve|delete|update|create/))

    for name <- @removed_writes ++ ["brando_list_entries", "brando_get_entry"] do
      assert {:ok, %{isError: true, structuredContent: %{"error" => "Unknown tool: " <> ^name}}} =
               BrandoMCP.Embedded.call_tool(
                 name,
                 %{"blueprint" => "pages", "confirm" => true},
                 @actor
               )
    end

    refute_received {:called, _, _, _}
  end

  test "an unprefixed registry name is not a tool" do
    assert {:ok, %{isError: true}} =
             BrandoMCP.Embedded.call_tool("search_entries", %{"query" => "x"}, @actor)

    refute_received {:called, _, _, _}
  end

  test "an in-process call carries the host's actor and conversation, not a caller's user" do
    assert {:ok, %{structuredContent: %{"actor_id" => 1}}} =
             BrandoMCP.Embedded.call_tool(
               "brando_content_search_entries",
               %{"query" => "Sommerro", "user_id" => 99},
               @actor,
               conversation_id: "c-1",
               attachments: %{"image1" => %{kind: :image, id: 12}}
             )

    assert_received {:called, "search_entries", %{"query" => "Sommerro"}, context}
    assert context.actor == @actor
    assert context.conversation_id == "c-1"
    assert context.attachments["image1"].id == 12
  end

  test "tool errors come back as MCP error results" do
    assert {:ok, %{isError: true, content: [%{text: "Operation 0: Unknown operation."}]}} =
             BrandoMCP.Embedded.call_tool(
               "brando_content_prepare_proposal",
               %{"operations" => []},
               @actor
             )
  end

  test "without an actor, tools refuse even when a user is configured" do
    assert {:ok, result, _} =
             BrandoMCP.Server.handle_call_tool("brando_content_list_content_types", %{}, %{})

    assert result.isError
    refute_received {:called, _, _, _}
  end

  test "a stored proposal is the one the next prepare_proposal refines" do
    state = %{brando_actor: @actor}
    args = %{"summary" => "s", "operations" => [%{"op" => "set_fields"}]}

    assert {:ok, %{structuredContent: %{"proposal_id" => first, "refines" => nil}}, state} =
             BrandoMCP.Server.handle_call_tool("brando_content_prepare_proposal", args, state)

    assert {:ok, %{structuredContent: %{"refines" => ^first}}, _state} =
             BrandoMCP.Server.handle_call_tool("brando_content_prepare_proposal", args, state)
  end

  test "results are encoded whole, as the admin agent sees them" do
    assert {:ok, %{structuredContent: %{"blocks" => [block]}}} =
             BrandoMCP.Embedded.call_tool("brando_content_entry_outline", %{}, @actor)

    deepest = Enum.reduce(1..8, block, fn _, %{"children" => [child]} -> child end)
    assert deepest == %{"text" => "deepest"}
  end

  test "an oversized result is refused, as in the admin" do
    assert {:ok, %{isError: true, content: [%{text: "The result was too large" <> _}]}} =
             BrandoMCP.Embedded.call_tool("brando_content_list_entry_media", %{}, @actor)
  end

  test "without Brando's registry there are no tools" do
    Application.put_env(:brando_mcp, :content_tools, Brando.Missing.Tools)
    assert BrandoMCP.Embedded.list_tools() == []

    assert {:ok, %{isError: true}} =
             BrandoMCP.Embedded.call_tool("brando_content_search_entries", %{}, @actor)
  end

  describe "where proposals come from" do
    setup do
      Application.put_env(:brando_mcp, :test_pid, self())
      on_exit(fn -> Application.delete_env(:brando_mcp, :test_pid) end)
    end

    test "the stdio server sends MCP and the client's title to Brando" do
      {:ok, state} = BrandoMCP.Server.init(actor: @actor)

      {:ok, _result, state} =
        BrandoMCP.Server.handle_initialize(
          %{
            "protocolVersion" => "2025-06-18",
            "clientInfo" => %{"name" => "claude-code", "title" => "Claude Code"}
          },
          state
        )

      {:ok, _result, _state} =
        BrandoMCP.Server.handle_call_tool("brando_content_prepare_proposal", %{}, state)

      assert_receive {:called, "prepare_proposal", _args,
                      %FakeTools.Context{origin: :mcp, client: "Claude Code"}}
    end

    test "the client's name falls back to its slug, kept to one short line" do
      {:ok, state} = BrandoMCP.Server.init(actor: @actor)
      long = "codex\nsecond line " <> String.duplicate("x", 200)

      {:ok, _result, state} =
        BrandoMCP.Server.handle_initialize(%{"clientInfo" => %{"name" => long}}, state)

      {:ok, _result, _state} =
        BrandoMCP.Server.handle_call_tool("brando_content_search_entries", %{}, state)

      assert_receive {:called, "search_entries", _args, %FakeTools.Context{client: "codex"}}
    end

    test "no client info leaves the client empty" do
      {:ok, state} = BrandoMCP.Server.init(actor: @actor)
      {:ok, _result, state} = BrandoMCP.Server.handle_initialize(%{}, state)

      {:ok, _result, _state} =
        BrandoMCP.Server.handle_call_tool("brando_content_search_entries", %{}, state)

      assert_receive {:called, "search_entries", _args,
                      %FakeTools.Context{origin: :mcp, client: nil}}
    end

    test "Embedded passes origin and client through, and leaves them out by default" do
      BrandoMCP.Embedded.call_tool("brando_content_search_entries", %{}, @actor,
        origin: :mcp,
        client: "Codex"
      )

      assert_receive {:called, "search_entries", _args,
                      %FakeTools.Context{origin: :mcp, client: "Codex"}}

      BrandoMCP.Embedded.call_tool("brando_content_search_entries", %{}, @actor)

      assert_receive {:called, "search_entries", _args,
                      %FakeTools.Context{origin: nil, client: nil}}
    end
  end
end
