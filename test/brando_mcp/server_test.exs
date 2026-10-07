defmodule BrandoMCP.ServerTest do
  use ExUnit.Case, async: false

  alias BrandoMCP.Test.FakeBlueprint

  setup do
    original = Application.get_all_env(:brando_mcp)

    Application.put_env(:brando_mcp, :blueprints, [FakeBlueprint])

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:brando_mcp) do
        Application.delete_env(:brando_mcp, key)
      end

      for {key, value} <- original do
        Application.put_env(:brando_mcp, key, value)
      end
    end)

    :ok
  end

  test "advertises Brando tools with safety annotations" do
    assert {:ok, tools, nil, _state} = BrandoMCP.Server.handle_list_tools(nil, %{})
    assert length(tools) == 23

    assert %{
             name: "brando_delete_entry",
             annotations: %{destructiveHint: true, readOnlyHint: false}
           } = Enum.find(tools, &(&1.name == "brando_delete_entry"))

    assert %{
             name: "brando_list_blueprints",
             annotations: %{readOnlyHint: true}
           } = Enum.find(tools, &(&1.name == "brando_list_blueprints"))

    assert %{
             name: "brando_prepare_translation",
             annotations: %{readOnlyHint: true}
           } = Enum.find(tools, &(&1.name == "brando_prepare_translation"))
  end

  test "returns structured MCP tool content" do
    assert {:ok, result, _state} =
             BrandoMCP.Server.handle_call_tool("brando_list_blueprints", %{}, %{})

    assert result.structuredContent["count"] == 1
    assert [%{type: "text", text: text}] = result.content
    assert {:ok, %{"count" => 1}} = Jason.decode(text)
  end

  test "returns a seed contract through the MCP tool boundary" do
    assert {:ok, result, _state} =
             BrandoMCP.Server.handle_call_tool(
               "brando_seed_contract",
               %{"blueprint" => "articles", "count" => 4},
               %{}
             )

    assert result.structuredContent["requested_count"] == 4
    assert "title" in result.structuredContent["input_schema"]["required"]
    assert "author_id" in result.structuredContent["input_schema"]["required"]
  end

  test "accepts the initialized lifecycle notification without a response" do
    assert {:noreply, %{connected: true}} =
             BrandoMCP.Server.handle_request(
               "notifications/initialized",
               %{},
               %{connected: true}
             )
  end

  test "round trips through ExMCP's in-memory transport" do
    {:ok, server} = start_supervised({BrandoMCP.Server, transport: :test})
    {:ok, client} = start_supervised({ExMCP.Client, transport: :test, server: server})

    assert {:ok, response} = ExMCP.Client.list_tools(client)
    assert Enum.any?(response.tools, &(&1["name"] == "brando_describe_blueprint"))

    assert {:ok, result} =
             ExMCP.Client.call_tool(client, "brando_describe_blueprint", %{
               "blueprint" => "articles"
             })

    assert result.structuredOutput["id"] == "demo-content-article"
  end
end
