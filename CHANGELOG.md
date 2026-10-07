# Changelog

## Unreleased

Part of [brandocms/brando#2996](https://github.com/brandocms/brando/issues/2996).
BrandoMCP no longer has a network endpoint. A remote endpoint, with OAuth 2.1,
two-factor authentication and a `:connect_mcp` permission, will come later as
its own work.

### Features

- **Proposals say which tool made them.** The stdio server passes `origin: :mcp` and the connecting client's name (its `clientInfo` title, else its name) into Brando's tool context, so the admin's review screen shows "From Claude Code via MCP". `BrandoMCP.Embedded.call_tool/4` takes `:origin` and `:client`. Brando versions without those fields ignore them.

### Breaking

- **`plug BrandoMCP` is gone.** `BrandoMCP` is no longer a Plug, and the
  `/brando/mcp` route, the `:at`, `:allow_remote_access` and
  `:allowed_origins` options and the loopback check went with it. Remove
  `plug BrandoMCP` from your Phoenix endpoint; the endpoint fails to compile
  until you do.
- **`mix brando.mcp --transport http` is gone**, along with `--host`, `--port`
  and `--include-brando`. `mix brando.mcp` serves stdio only.
- **`mix brando.mcp` is development only.** It refuses to start with
  `MIX_ENV=prod` or inside a release.
- **`mix brando.mcp` runs as a named Brando user.** Set
  `config :brando_mcp, user: "dev@example.com"` or pass `--user`. Without one
  it refuses to start. `:user` must be an email: `:system` and user structs are
  no longer accepted.
- **Read and propose only.** The tools are Brando's content-proposal tools
  (`brando_content_*`), the same set the admin's content agent uses, taken from
  the host's `Brando.Content.Proposals.Tools`. Removed:
  - the tools that wrote directly: `brando_create_entry`,
    `brando_update_entry`, `brando_delete_entry`, `brando_apply_seed_batch`
    and `brando_apply_translation`;
  - the generic tools, which did not check the user's permissions:
    `brando_system_info`, `brando_list_blueprints`,
    `brando_describe_blueprint`, `brando_list_entries`, `brando_get_entry`,
    `brando_seed_contract`, `brando_validate_seed_batch`,
    `brando_prepare_translation` and `brando_validate_translation`;
  - the `brando://` resources and the `brando_content_workflow` prompt.
- **Removed configuration:** `:writes_enabled` (and
  `BRANDO_MCP_WRITES_ENABLED`), `:writable_blueprints`, `:user_resolver`,
  `:adapter` (and the `BrandoMCP.Adapter` behaviour), `:blueprints`,
  `:include_brando_blueprints`, `:default_page_size`, `:max_page_size`,
  `:max_seed_batch_size`, `:serializer_depth`, `:translation_content_adapter`
  and `:repo`.
- `BrandoMCP.start_link/1` is gone; `BrandoMCP.Server.start_link/1` starts
  only the stdio transport.

### Changed

- The tool list is read from the host's Brando registry, so it now includes
  every tool the admin's agent has, with Brando's own descriptions and
  parameters.
- Results are encoded whole, as the admin agent sees them, and a result over
  24 KB is refused as in the admin. They were cut at a depth of three before.
- Within one stdio session, each `brando_content_prepare_proposal` refines the
  session's previous proposal, as in the admin's assistant.

### Unchanged

- `BrandoMCP.Embedded.call_tool/4` and `BrandoMCP.Embedded.list_tools/0`
  keep their signatures and behaviour for the `brando_content_*` tools. The
  removed tools above are no longer callable through them.
