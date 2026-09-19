defmodule BrandoMCP.PlugTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

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

  test "serves MCP from the host Plug pipeline" do
    conn =
      :post
      |> conn("/brando/mcp", initialize_request())
      |> put_req_header("content-type", "application/json")
      |> BrandoMCP.call(BrandoMCP.init([]))

    assert conn.halted
    assert conn.status == 200
    assert [session_id] = get_resp_header(conn, "mcp-session-id")
    assert session_id != ""

    assert %{
             "id" => 1,
             "jsonrpc" => "2.0",
             "result" => %{
               "serverInfo" => %{"name" => "brando"},
               "capabilities" => %{"tools" => %{}}
             }
           } = Jason.decode!(conn.resp_body)
  end

  test "leaves unrelated requests in the client pipeline" do
    conn = conn(:get, "/admin") |> BrandoMCP.call(BrandoMCP.init([]))

    refute conn.halted
    assert conn.state == :unset
  end

  test "supports a custom mount path" do
    conn =
      :post
      |> conn("/internal/mcp", initialize_request())
      |> put_req_header("content-type", "application/json")
      |> BrandoMCP.call(BrandoMCP.init(at: "/internal/mcp"))

    assert conn.halted
    assert conn.status == 200
  end

  test "rejects remote connections by default" do
    conn =
      :post
      |> conn("/brando/mcp", initialize_request())
      |> Map.put(:remote_ip, {10, 0, 0, 2})
      |> BrandoMCP.call(BrandoMCP.init([]))

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body =~ "does not accept remote connections"
  end

  test "rejects browser-originated requests by default" do
    conn =
      :post
      |> conn("/brando/mcp", initialize_request())
      |> put_req_header("origin", "http://localhost")
      |> BrandoMCP.call(BrandoMCP.init([]))

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body =~ "Origin header"
  end

  test "can deliberately allow remote connections" do
    conn =
      :post
      |> conn("/brando/mcp", initialize_request())
      |> Map.put(:remote_ip, {10, 0, 0, 2})
      |> BrandoMCP.call(BrandoMCP.init(allow_remote_access: true))

    assert conn.halted
    assert conn.status == 200
  end

  test "must be mounted before body parsers" do
    parsed_conn =
      :post
      |> conn("/brando/mcp", initialize_request())
      |> Map.put(:body_params, %{})

    assert_raise RuntimeError, ~r/before Plug.Parsers/, fn ->
      BrandoMCP.call(parsed_conn, BrandoMCP.init([]))
    end
  end

  defp initialize_request do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-11-25",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "brando-mcp-test", "version" => "1.0.0"}
      }
    })
  end
end
