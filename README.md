# BrandoMCP

BrandoMCP exposes [Brando CMS](https://github.com/brandocms/brando)'s content
tools through the Model Context Protocol.

The tools are Brando's own `Brando.Content.Proposals.Tools`: the same set the
Brando admin's content agent uses. They read content and prepare changes for
a person to review. No tool approves or applies anything; that happens only
when the user confirms in the Brando admin.

BrandoMCP has no network endpoint. It works in two ways:

- **In-process**, for a host that has already authenticated a user
  (`BrandoMCP.Embedded`).
- **Over stdio, in development only**, for a local coding agent such as
  Claude Code (`mix brando.mcp`).

## Tools

Each tool in Brando's registry is exposed with a `brando_content_` prefix,
with the registry's description and parameters. With a current Brando these
include:

| Tool | Purpose |
| --- | --- |
| `brando_content_list_content_types` | Editable content types with block fields |
| `brando_content_describe_content_type` | Editable fields and block fields |
| `brando_content_search_entries` | Find entries the user can edit |
| `brando_content_entry_outline` | Fields and an outline of the blocks |
| `brando_content_list_modules` | Modules a block field accepts |
| `brando_content_describe_module` | Text slots, media slots and variables |
| `brando_content_search_assets` | Images, videos and files in the library |
| `brando_content_prepare_proposal` | Validate changes and store them for review |

The list follows the Brando version in the host application, so tools added
to Brando's registry appear here without a BrandoMCP release. Over stdio there
is no admin conversation, so the tools that work on a conversation's
attachments (`brando_content_list_attachments`, `brando_content_attach_folder`)
have nothing to work on.

Results are bounded as in the admin: at most 20 results and 160-character
excerpts, and a result over 24 KB is refused with a request to narrow it.

## Development use over stdio

`mix brando.mcp` serves the tools over stdio to a local coding agent, as a
named Brando user. Every tool call carries that user's own permissions: the
agent can read and propose only what that user could in the admin.

The task:

- refuses to start with `MIX_ENV=prod` or inside a release;
- has no network transport;
- has no default user, never runs as `:system`, and never takes its
  identity from the MCP client.

Add BrandoMCP as a development dependency of the Brando application:

```elixir
def deps do
  [
    {:brando_mcp, github: "brandocms/brando_mcp", only: :dev}
  ]
end
```

Name the user to run as, by email:

```elixir
# config/dev.exs
config :brando_mcp, user: "dev@example.com"
```

`--user` overrides the configured user:

```sh
mix brando.mcp --user dev@example.com
```

The user must be an active Brando user. Prefer an editor account with the
permissions you want the agent to have over a superuser; the task notes on
stderr when it runs as a superuser.

### Claude Code

```sh
claude mcp add brando -- mix brando.mcp --user dev@example.com
```

Or in the project's `.mcp.json`:

```json
{
  "mcpServers": {
    "brando": {
      "command": "mix",
      "args": ["brando.mcp", "--user", "dev@example.com"],
      "env": {"MIX_ENV": "dev"}
    }
  }
}
```

### Other stdio clients

Any MCP client that launches a stdio server works the same way: the command
is `mix`, the arguments are `brando.mcp --user <email>`, and the working
directory is the Brando application's root.

Compile the application first (`mix compile`). Standard output carries only
JSON-RPC messages, and the task keeps the application's compiler output off
it, but dependencies compiled while Mix looks up the task can still print
there.

### Reviewing proposals

`brando_content_prepare_proposal` stores a proposal under the user. Within
one session, each new proposal refines the previous one, as in the admin's
assistant. Approving and applying happen in the Brando admin.

Each tool call runs inside `Brando.Activity.with_source(:mcp, …)` with the
client's name, as Brando's own MCP endpoint does, so anything a call records in
**Configuration → Activity** names the client rather than the user it runs as.
Brando versions without `with_source/3` run the call unattributed.

## In-process use

A host that has already authenticated a user calls tools as plain function
calls. Nothing listens and nothing is mounted:

```elixir
{:ok, result} =
  BrandoMCP.Embedded.call_tool("brando_content_search_entries", %{"query" => "Sommerro"}, current_user,
    conversation_id: conversation.id,
    attachments: %{"image1" => %{kind: :image, id: 12, label: "lobby.jpg"}}
  )
```

The actor is the one the host passes, never a `user_id` argument. The Brando
admin's content agent does not need BrandoMCP at all: it calls the same
`Brando.Content.Proposals.Tools` directly.

## Configuration

```elixir
config :brando_mcp,
  user: "dev@example.com"   # the Brando user mix brando.mcp runs as
```

Brando is intentionally not a dependency of this package. BrandoMCP runs
inside the host application's BEAM and uses the Brando version already loaded
there.

## Development

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

## License

MIT
