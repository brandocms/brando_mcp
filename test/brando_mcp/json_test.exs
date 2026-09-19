defmodule BrandoMCP.JSONTest do
  use ExUnit.Case, async: true

  alias BrandoMCP.JSON

  test "normalizes JSON values and redacts secrets" do
    normalized =
      JSON.normalize(%{
        password: "secret",
        api_key: "key",
        date: ~D[2026-07-30],
        tuple: {:ok, 1},
        nested: %{title: "Visible"}
      })

    assert normalized["password"] == "[REDACTED]"
    assert normalized["api_key"] == "[REDACTED]"
    assert normalized["date"] == "2026-07-30"
    assert normalized["tuple"] == ["ok", 1]
    assert normalized["nested"]["title"] == "Visible"
  end

  test "base64 encodes invalid UTF-8 binaries" do
    assert %{"encoding" => "base64", "data" => _data} = JSON.normalize(<<255>>)
  end
end
