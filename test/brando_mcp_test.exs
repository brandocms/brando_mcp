defmodule BrandoMCPTest do
  use ExUnit.Case, async: true

  test "BrandoMCP is no longer a Plug, so it cannot be mounted on an endpoint" do
    Code.ensure_loaded!(BrandoMCP)

    behaviours =
      BrandoMCP.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

    refute Plug in behaviours
    refute function_exported?(BrandoMCP, :init, 1)
    refute function_exported?(BrandoMCP, :call, 2)
  end

  test "no code path starts or mounts a network transport" do
    refute function_exported?(BrandoMCP, :start_link, 1)

    for file <- Path.wildcard("lib/**/*.ex") do
      refute File.read!(file) =~ ~r/:http\b|HttpPlug|Plug\.|Cowboy|Bandit|:gen_tcp|:ranch/,
             "#{file} refers to a network transport"
    end
  end
end
