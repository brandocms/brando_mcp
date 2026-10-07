defmodule BrandoMCP.Server do
  @moduledoc """
  MCP server exposing Brando blueprint and content operations.

  The server supports stdio, Streamable HTTP, BEAM-local, and in-memory test
  transports through ExMCP.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "brando", version: "0.1.0"

  alias BrandoMCP.Tools

  tool "brando_system_info",
       "Report Brando, host application, server safety, and pagination configuration." do
    title("Brando system information")
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.system_info/2)
  end

  tool "brando_list_blueprints",
       "List compiled Brando blueprints available to this host application." do
    title("List Brando blueprints")

    param(:include_brando, :boolean,
      default: false,
      description: "Include Brando's built-in Page and Fragment blueprints."
    )

    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.list_blueprints/2)
  end

  tool "brando_describe_blueprint",
       "Describe a Brando blueprint's fields, relations, assets, traits, forms, and listings." do
    title("Describe a Brando blueprint")

    param(:blueprint, :string,
      required: true,
      description: "Blueprint module, blueprint id, schema, singular, or plural name."
    )

    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.describe_blueprint/2)
  end

  tool "brando_list_entries",
       "List entries through the selected blueprint's generated Brando context query." do
    title("List Brando entries")
    param(:blueprint, :string, required: true)
    param(:filter, :object, description: "Blueprint context filters.")
    param(:status, :string)
    param(:language, :string)
    param(:order, :string, description: "Brando order string, for example `asc title`.")
    param(:fields, {:array, :string}, description: "Scalar fields to select.")
    param(:preload, {:array, :string}, description: "Associations to preload.")
    param(:limit, :integer, default: 25)
    param(:offset, :integer, default: 0)
    param(:with_deleted, :boolean, default: false)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.list_entries/2)
  end

  tool "brando_get_entry",
       "Read one entry by primary key through the selected blueprint's Brando context." do
    title("Get a Brando entry")
    param(:blueprint, :string, required: true)

    param(:id, :string,
      required: true,
      schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]}
    )

    param(:fields, {:array, :string}, description: "Scalar fields to select.")
    param(:preload, {:array, :string}, description: "Associations to preload.")
    param(:revision, :integer, description: "Read a specific revision when supported.")
    param(:with_deleted, :boolean, default: false)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.get_entry/2)
  end

  tool "brando_create_entry",
       "Create an entry through its generated Brando context. Writes must be enabled and require a Brando user." do
    title("Create a Brando entry")
    param(:blueprint, :string, required: true)
    param(:attributes, :object, required: true)
    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})

    annotations(%{
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    })

    run(&Tools.create_entry/2)
  end

  tool "brando_update_entry",
       "Update an entry through its generated Brando context. Writes must be enabled and require a Brando user." do
    title("Update a Brando entry")
    param(:blueprint, :string, required: true)

    param(:id, :string,
      required: true,
      schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]}
    )

    param(:attributes, :object, required: true)
    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})

    annotations(%{
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    })

    run(&Tools.update_entry/2)
  end

  tool "brando_delete_entry",
       "Delete or soft-delete an entry through its generated Brando context. Requires enabled writes, a Brando user, and confirm=true." do
    title("Delete a Brando entry")
    param(:blueprint, :string, required: true)

    param(:id, :string,
      required: true,
      schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]}
    )

    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})

    param(:confirm, :boolean,
      required: true,
      description: "Must be true after direct user confirmation."
    )

    annotations(%{
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    })

    run(&Tools.delete_entry/2)
  end

  tool "brando_seed_contract",
       "Describe the generation contract for seeding one Brando blueprint, including defaults, required fields, relations, assets, and block inputs." do
    title("Get a Brando seed contract")
    param(:blueprint, :string, required: true)
    param(:count, :integer, default: 1, description: "Intended number of seed entries.")
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.seed_contract/2)
  end

  tool "brando_validate_seed_batch",
       "Validate an LLM-generated seed batch with the blueprint's real Brando changesets without inserting entries." do
    title("Validate a Brando seed batch")
    param(:blueprint, :string, required: true)

    param(:entries, {:array, :object},
      required: true,
      description:
        "Entries shaped as {ref, attributes}. Attribute values may reference an earlier entry with {\"$ref\":\"ref\"}."
    )

    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.validate_seed_batch/2)
  end

  tool "brando_apply_seed_batch",
       "Insert a previously reviewed seed batch through Brando contexts in one database transaction." do
    title("Apply a Brando seed batch")
    param(:blueprint, :string, required: true)
    param(:entries, {:array, :object}, required: true)
    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})

    param(:confirm, :boolean,
      required: true,
      description: "Must be true after the user reviews the seed preview."
    )

    annotations(%{
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    })

    run(&Tools.apply_seed_batch/2)
  end

  tool "brando_prepare_translation",
       "Collect all translatable fields and nested block content from an entry into a provider-neutral manifest for the connected MCP client to translate." do
    title("Prepare a Brando translation")
    param(:blueprint, :string, required: true)
    param(:id, :string, required: true, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})
    param(:target_language, :string, required: true)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.prepare_translation/2)
  end

  tool "brando_validate_translation",
       "Validate translated manifest values, source freshness, HTML, and template placeholders without writing." do
    title("Validate a Brando translation")
    param(:blueprint, :string, required: true)
    param(:id, :string, required: true, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})
    param(:target_language, :string, required: true)
    param(:source_digest, :string, required: true)

    param(:translations, {:array, :object},
      required: true,
      description:
        "Values shaped as {key, translation}, using every key from prepare_translation."
    )

    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.validate_translation/2)
  end

  tool "brando_apply_translation",
       "Create a target-language draft, apply validated translations to fields and blocks, link alternates, regenerate slugs, and re-render content." do
    title("Apply a Brando translation")
    param(:blueprint, :string, required: true)
    param(:id, :string, required: true, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})
    param(:target_language, :string, required: true)
    param(:source_digest, :string, required: true)
    param(:translations, {:array, :object}, required: true)
    param(:user_id, :string, schema: %{oneOf: [%{type: "integer"}, %{type: "string"}]})

    param(:confirm, :boolean,
      required: true,
      description: "Must be true after the user reviews the translation."
    )

    annotations(%{
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    })

    run(&Tools.apply_translation/2)
  end

  # Content-proposal tools. They run only for the actor the host puts in the
  # handler state (see BrandoMCP.Embedded); none approves or applies content.

  tool "brando_content_list_content_types",
       "List the content types the actor can edit that have block fields." do
    title("List editable content types")
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_list_content_types/2)
  end

  tool "brando_content_describe_content_type",
       "Describe a content type's editable fields and block fields." do
    title("Describe a content type")
    param(:content_type, :string, required: true)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_describe_content_type/2)
  end

  tool "brando_content_search_entries", "Search entries the actor can edit by title." do
    title("Search entries")
    param(:query, :string, required: true)
    param(:content_type, :string)
    param(:limit, :integer, default: 10)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_search_entries/2)
  end

  tool "brando_content_entry_outline",
       "Read an entry's fields and an outline of its root blocks with their uids." do
    title("Outline an entry")
    param(:content_type, :string, required: true)
    param(:id, :integer, required: true)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_entry_outline/2)
  end

  tool "brando_content_list_modules", "List the modules a block field accepts." do
    title("List modules")
    param(:content_type, :string, required: true)
    param(:field, :string, default: "blocks")
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_list_modules/2)
  end

  tool "brando_content_describe_module",
       "Describe a module's text slots, media slots and variables." do
    title("Describe a module")
    param(:module, :string, required: true)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_describe_module/2)
  end

  tool "brando_content_list_attachments", "List the media attached to the conversation." do
    title("List attachments")
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_list_attachments/2)
  end

  tool "brando_content_search_assets", "Search the media library for images or videos." do
    title("Search media")
    param(:kind, :string, required: true, enum: ["image", "video"])
    param(:query, :string)
    param(:limit, :integer, default: 10)
    annotations(%{readOnlyHint: true, destructiveHint: false, openWorldHint: false})
    run(&Tools.content_search_assets/2)
  end

  tool "brando_content_prepare_proposal",
       "Validate a set of content operations and store it for the user to review in the Brando admin. Nothing is saved until the user approves it there." do
    title("Prepare a content proposal")
    param(:summary, :string, required: true)
    param(:operations, {:array, :object}, required: true)

    annotations(%{
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    })

    run(&Tools.content_prepare_proposal/2)
  end

  resource "brando://system", "Brando MCP runtime and safety configuration." do
    name("Brando system information")
    mime_type("application/json")
    read(&Tools.system_resource/2)
  end

  resource "brando://blueprints", "Index of available Brando blueprints." do
    name("Brando blueprints")
    mime_type("application/json")
    read(&Tools.blueprints_resource/2)
  end

  resource_template "brando://blueprints/{blueprint}",
                    "Full metadata for one Brando blueprint." do
    name("Brando blueprint metadata")
    mime_type("application/json")
    param(:blueprint, :string, required: true)
    read(&Tools.blueprint_resource/2)
  end

  prompt "brando_content_workflow",
         "A safe inspect-before-mutate workflow for Brando content tasks." do
    title("Brando content workflow")
    arg(:blueprint, description: "Blueprint to work with.")
    arg(:objective, description: "Content task to accomplish.")
    render(&Tools.workflow_prompt/2)
  end

  # ExMCP's stdio dispatcher forwards lifecycle notifications to a custom
  # request handler. Treat the standard post-initialize notification as the
  # one-way message it is, so no JSON-RPC response is written for a nil id.
  def handle_request("notifications/initialized", _params, state), do: {:noreply, state}
end
