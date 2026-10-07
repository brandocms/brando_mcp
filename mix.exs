defmodule BrandoMCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :brando_mcp,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Model Context Protocol server for Brando CMS",
      package: package(),
      source_url: "https://github.com/brandocms/brando_mcp"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BrandoMCP.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_mcp, "~> 1.0.0-rc.4"},
      {:jason, "~> 1.4"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/brandocms/brando_mcp"}
    ]
  end
end
