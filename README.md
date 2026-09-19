# BrandoMCP

BrandoMCP exposes a running [Brando CMS](https://github.com/brandocms/brando)
application through the Model Context Protocol.

It discovers the host application's compiled blueprints and uses Brando's
generated context functions. There is no parallel CRUD layer and no arbitrary
module lookup.

## Capabilities

The server currently exposes:

| Tool | Purpose |
| --- | --- |
| `brando_system_info` | Brando version, host OTP app, limits, and write status |
| `brando_list_blueprints` | List compiled application blueprints |
| `brando_describe_blueprint` | Fields, relations, assets, traits, forms, and listings |
| `brando_list_entries` | Paginated, filtered context queries |
| `brando_get_entry` | Read one entry, optional fields/preloads/revision |
| `brando_create_entry` | Create through the generated Brando context |
| `brando_update_entry` | Update through the generated Brando context |
| `brando_delete_entry` | Delete or soft-delete through the generated Brando context |
| `brando_seed_contract` | Describe an LLM-ready seed contract for a blueprint |
| `brando_validate_seed_batch` | Preview generated seed entries through real changesets |
| `brando_apply_seed_batch` | Insert a reviewed seed batch in one transaction |
| `brando_prepare_translation` | Collect fields and nested block content for translation |
| `brando_validate_translation` | Check source freshness, keys, HTML, and placeholders |
| `brando_apply_translation` | Duplicate, translate, link, slug, and render a target draft |

It also provides system and blueprint resources plus a
`brando_content_workflow` prompt.

## Installation

Add BrandoMCP to a Brando application's dependencies:

```elixir
def deps do
  [
    {:brando_mcp, path: "../brando_mcp", only: :dev, runtime: true}
  ]
end
```

Then fetch and compile dependencies:

```sh
mix deps.get
mix compile
```

Brando is intentionally not a dependency of this package. BrandoMCP runs
inside the host application's BEAM and discovers the Brando version already
loaded there.

## Phoenix integration

Mount BrandoMCP in the application's Phoenix endpoint, before the code
reloader and `Plug.Parsers`:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # sockets, static files, etc.

  if Code.ensure_loaded?(BrandoMCP) do
    plug BrandoMCP
  end

  if code_reloading? do
    # Phoenix.LiveReloader, Phoenix.CodeReloader, etc.
  end

  plug Plug.RequestId
  plug Plug.Parsers, ...
  plug MyAppWeb.Router
end
```

The client application's existing server now exposes Streamable HTTP at:

```text
http://localhost:4000/brando/mcp
```

`plug BrandoMCP` intercepts only `/brando/mcp` and its transport subpaths.
Every other request continues through the endpoint unchanged. BrandoMCP does
not bind a port or start another web server.

The mount path can be changed:

```elixir
plug BrandoMCP, at: "/internal/brando"
```

For security, the endpoint accepts only loopback connections and rejects
requests carrying an `Origin` header by default. Deliberately exposing the
endpoint on the network requires:

```elixir
plug BrandoMCP,
  allow_remote_access: true,
  allowed_origins: ["https://your-trusted-mcp-client.example"]
```

## Optional standalone transport

Some MCP clients support only stdio. For those clients, `mix brando.mcp`
remains available as a fallback:

```sh
mix brando.mcp
```

This boots the host Mix application, starts an MCP stdio transport, and keeps
the task alive until the client disconnects. It is not needed when using the
Phoenix endpoint.

A standalone Streamable HTTP listener is also available for non-Phoenix
applications:

```sh
mix brando.mcp --transport http --host 127.0.0.1 --port 4001
```

## Safety and writes

Reads work by default. Mutating tools are advertised with MCP safety
annotations but reject calls until explicitly enabled:

```elixir
# config/dev.exs
config :brando_mcp,
  writes_enabled: true,
  writable_blueprints: [
    MyApp.Pages.Page,
    "myapp-projects-project"
  ]
```

Create, update, and delete calls require a Brando `user_id`. The default user
resolver calls `Brando.Users.get_user/1`. A host can replace it:

```elixir
config :brando_mcp,
  user_resolver: {MyApp.MCPUsers, :get_user},
  writes_enabled: true
```

The resolver may be a one-argument function, `{module, function}`, or
`{module, function, extra_args}` and must return a user or
`{:ok, user}`. A fixed user, including `:system`, must be deliberately
configured:

```elixir
config :brando_mcp,
  writes_enabled: true,
  user: :system
```

Additional safeguards:

- Delete requires `confirm: true`.
- Seed and translation apply operations require `confirm: true`.
- List limits are clamped to `100` by default.
- Seed batches are limited to `50` entries by default.
- Blueprint, field, preload, and filter names resolve only to loaded atoms.
- Passwords, tokens, secrets, and keys are redacted from tool output.
- Associations are loaded only when explicitly requested.

`BRANDO_MCP_WRITES_ENABLED=true` is also supported for controlled local
environments.

## LLM-assisted content seeding

Content generation happens in the connected MCP client, not inside the
Brando server:

1. Call `brando_seed_contract` with a blueprint such as `Employee` and the
   desired count.
2. The MCP client's LLM generates entries from the returned JSON schema,
   defaults, relation/asset inputs, and block-field instructions.
3. Call `brando_validate_seed_batch`. BrandoMCP runs the real blueprint
   changeset with `cast_blocks: true` and returns an entry-by-entry preview.
4. After the user reviews the preview, call `brando_apply_seed_batch` with
   the same entries and `confirm: true`.

Entries are shaped as:

```json
{
  "ref": "employee-ada",
  "attributes": {
    "name": "Ada Lovelace",
    "manager_id": {"$ref": "employee-charles"},
    "status": "draft"
  }
}
```

`$ref` values are batch-local handles. BrandoMCP validates their dependency
graph, resolves them to inserted ids, and rolls the whole batch back when any
entry fails. Cycles, unknown handles, and duplicate handles are rejected.

Block-enabled blueprints expose their `entry_<field>` association inputs in
the contract. Image, file, video, and gallery fields currently accept existing
Brando media ids. Media generation and upload should be a separate MCP
workflow so the MCP client can use whichever image model or asset source the
user has selected.

## Client-LLM translation

Translation also uses the connected MCP client's LLM. BrandoMCP never asks
ReqLLM, OpenAI, Anthropic, or another provider to generate the translated
text.

1. `brando_prepare_translation` reads the source entry and uses Brando's
   content collector to return every translatable field, block var, ref,
   gallery override, table value, and identifier metadata value.
2. The MCP client's LLM translates each manifest item.
3. `brando_validate_translation` verifies the source digest, exact key set,
   non-empty values, unchanged HTML tags/attributes, and unchanged template
   placeholders.
4. With `confirm: true`, `brando_apply_translation` duplicates the source as
   a target-language draft, links alternates, applies translated values,
   regenerates slugs, and re-renders block content in one transaction.

The default `:translation_content_adapter` is
`Brando.AI.Translation`, but BrandoMCP calls only its public content
collection and content-application functions. Its provider-calling
translation function is not used. A host can replace this adapter when it has
custom content types:

```elixir
config :brando_mcp,
  translation_content_adapter: MyApp.MCPTranslationContent
```

The adapter must implement `collect_translatable_content/2` and
`apply_translations/3` with the same tagged tuple contract used by
`Brando.AI.Translation`.

## Configuration

```elixir
config :brando_mcp,
  include_brando_blueprints: false,
  default_page_size: 25,
  max_page_size: 100,
  max_seed_batch_size: 50,
  serializer_depth: 3,
  writes_enabled: false,
  writable_blueprints: :all
```

Set `:adapter` to a module implementing `BrandoMCP.Adapter` to add a tenant or
authorization boundary without changing the MCP protocol layer.

## Development

```sh
mix deps.get
mix format --check-formatted
mix test
```

## License

MIT
