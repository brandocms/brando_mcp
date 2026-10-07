defmodule BrandoMCP.ServerTest do
  use ExUnit.Case, async: false

  @user %{id: 7, email: "dev@example.com", active: true, deleted_at: nil, role: :editor}

  setup do
    BrandoMCP.Test.Env.setup()
    Application.put_env(:ex_mcp, :stdio_startup_delay, 0)
    on_exit(fn -> Application.delete_env(:ex_mcp, :stdio_startup_delay) end)
  end

  test "initialize advertises tools only" do
    assert {:ok, %{"capabilities" => capabilities, "serverInfo" => %{"name" => "brando"}}, _} =
             BrandoMCP.Server.handle_initialize(%{"protocolVersion" => "2025-06-18"}, %{})

    assert capabilities == %{"tools" => %{}}
  end

  test "lifecycle notifications get no response and ping an empty one" do
    assert {:noreply, %{}} =
             BrandoMCP.Server.handle_request("notifications/initialized", %{}, %{})

    assert {:reply, %{}, %{}} = BrandoMCP.Server.handle_request("ping", %{}, %{})

    assert {:error, "Method not found: x/y", %{}} =
             BrandoMCP.Server.handle_request("x/y", %{}, %{})
  end

  test "an MCP client lists and calls tools as the server's actor" do
    {:ok, server} =
      start_supervised(
        {ExMCP.Server.HandlerServer,
         handler: BrandoMCP.Server, transport: :test, handler_args: [actor: @user]}
      )

    {:ok, client} = start_supervised({ExMCP.Client, transport: :test, server: server})

    assert {:ok, response} = ExMCP.Client.list_tools(client)
    assert Enum.any?(response.tools, &(&1["name"] == "brando_content_search_entries"))

    assert {:ok, result} =
             ExMCP.Client.call_tool(client, "brando_content_search_entries", %{
               "query" => "Sommerro",
               "user_id" => 1
             })

    assert result.structuredOutput["actor_id"] == 7
    assert_receive {:called, "search_entries", %{"query" => "Sommerro"}, %{actor: @user}}
  end

  test "serves JSON-RPC over stdio, end to end, as the named user" do
    requests = [
      %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-06-18",
          capabilities: %{},
          clientInfo: %{name: "superuser@example.com", version: "1"}
        }
      },
      %{jsonrpc: "2.0", method: "notifications/initialized"},
      %{jsonrpc: "2.0", id: 2, method: "tools/list", params: %{}},
      %{
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: %{
          name: "brando_content_search_entries",
          arguments: %{query: "Sommerro", user_id: 1}
        }
      },
      %{
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: %{name: "brando_update_entry", arguments: %{blueprint: "pages", id: 1}}
      },
      %{jsonrpc: "2.0", id: 5, method: "ping"}
    ]

    {pid, output} = serve_stdio("dev@example.com", requests)

    responses = Map.new(output, &{&1["id"], &1})
    assert map_size(responses) == 5, "one response per request, none for the notification"

    assert %{"serverInfo" => %{"name" => "brando"}, "capabilities" => %{"tools" => %{}}} =
             responses[1]["result"]

    names = Enum.map(responses[2]["result"]["tools"], & &1["name"])
    assert "brando_content_prepare_proposal" in names
    refute "brando_update_entry" in names

    assert %{"structuredContent" => %{"actor_id" => 7}} = responses[3]["result"]
    assert_receive {:called, "search_entries", %{"query" => "Sommerro"}, %{actor: %{id: 7}}}

    assert %{"isError" => true, "content" => [%{"text" => "Unknown tool: brando_update_entry"}]} =
             responses[4]["result"]

    assert responses[5]["result"] == %{}
    refute_received {:called, _, _, _}

    refute Process.alive?(pid)
  end

  # Runs BrandoMCP.Stdio.start/1 with `requests` on standard input, until
  # standard input closes, and returns the decoded lines of standard output.
  defp serve_stdio(email, requests) do
    input = Enum.map_join(requests, &(Jason.encode!(&1) <> "\n"))
    {:ok, io} = StringIO.open(input)
    group_leader = Process.group_leader()
    Process.group_leader(self(), io)

    {:ok, pid, _user} =
      try do
        BrandoMCP.Stdio.start(email)
      after
        Process.group_leader(self(), group_leader)
      end

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

    {_input, output} = StringIO.contents(io)
    lines = output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    {pid, lines}
  end
end
