defmodule BrandoMCP do
  @moduledoc """
  Model Context Protocol tools for Brando CMS.

  BrandoMCP exposes Brando's content-proposal tools — the same set the Brando
  admin's content agent uses — in two ways, neither of which listens on the
  network:

    * `BrandoMCP.Embedded` — in-process calls for a host that has already
      authenticated a user.
    * `mix brando.mcp` — a development-only stdio server for local coding
      agents, running as a named Brando user (see `BrandoMCP.Stdio`).

  The tools read content and prepare proposals. Approving and applying a
  proposal happens only in the Brando admin.
  """
end
