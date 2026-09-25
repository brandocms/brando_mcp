defmodule BrandoMCP.ContentTest do
  use ExUnit.Case, async: false

  defmodule FakeTools do
    defmodule Context do
      defstruct [:actor, :conversation_id, :proposal_id, attachments: %{}]
    end

    def call(name, args, %Context{} = context) do
      send(self(), {:called, name, args, context})

      if name == "prepare_proposal",
        do: {:error, "Operation 0: Unknown operation."},
        else: {:ok, %{"ok" => true}}
    end
  end

  setup do
    original = Application.get_all_env(:brando_mcp)
    Application.put_env(:brando_mcp, :content_tools, FakeTools)
    Application.put_env(:brando_mcp, :user, %{id: 99, name: "Configured"})

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:brando_mcp),
          do: Application.delete_env(:brando_mcp, key)

      for {key, value} <- original, do: Application.put_env(:brando_mcp, key, value)
    end)
  end

  test "content tools are listed with safety annotations" do
    tools = BrandoMCP.Embedded.list_tools()
    names = Enum.map(tools, & &1.name)
    assert "brando_content_search_entries" in names
    assert "brando_content_prepare_proposal" in names
    refute Enum.any?(names, &(&1 =~ ~r/content_(apply|approve)/))

    assert %{annotations: %{readOnlyHint: true}} =
             Enum.find(tools, &(&1.name == "brando_content_entry_outline"))

    assert %{annotations: %{destructiveHint: false}} =
             Enum.find(tools, &(&1.name == "brando_content_prepare_proposal"))
  end

  test "an in-process call carries the host's actor and conversation, not a caller's user" do
    actor = %{id: 1, name: "Editor"}

    assert {:ok, %{structuredContent: %{"ok" => true}}} =
             BrandoMCP.Embedded.call_tool(
               "brando_content_search_entries",
               %{"query" => "Sommerro", "user_id" => 99},
               actor,
               conversation_id: "c-1",
               attachments: %{"image1" => %{kind: :image, id: 12}}
             )

    assert_received {:called, "search_entries", %{"query" => "Sommerro"}, context}
    assert context.actor == actor
    assert context.conversation_id == "c-1"
    assert context.attachments["image1"].id == 12
  end

  test "tool errors come back as MCP error results" do
    assert {:ok, %{isError: true}} =
             BrandoMCP.Embedded.call_tool(
               "brando_content_prepare_proposal",
               %{"operations" => []},
               %{id: 1}
             )
  end

  test "without a host actor, content tools refuse even when a user is configured" do
    assert {:ok, result, _} =
             BrandoMCP.Server.handle_call_tool("brando_content_list_content_types", %{}, %{})

    assert result.isError
    refute_received {:called, _, _, _}
  end
end
