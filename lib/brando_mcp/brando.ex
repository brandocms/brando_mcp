defmodule BrandoMCP.Brando do
  @moduledoc false

  @behaviour BrandoMCP.Adapter

  alias BrandoMCP.{Config, Seed, Translation}

  @blueprint Module.concat(["Brando", "Blueprint"])
  @attributes Module.concat(["Brando", "Blueprint", "Attributes"])
  @assets Module.concat(["Brando", "Blueprint", "Assets"])
  @relations Module.concat(["Brando", "Blueprint", "Relations"])
  @association_key Module.concat(["Brando", "Blueprint", "AssociationKey"])
  @forms Module.concat(["Brando", "Blueprint", "Forms"])
  @runtime_config Module.concat(["Brando", "RuntimeConfig"])
  @users Module.concat(["Brando", "Users"])
  @content_blocks Module.concat(["Brando", "Content", "Blocks"])
  @utils Module.concat(["Brando", "Utils"])
  @seed_system_fields ~w(
    id
    creator_id
    inserted_at
    updated_at
    deleted_at
    rendered_at
    alternates
    revision
  )a

  @impl true
  def system_info do
    with :ok <- ensure_brando() do
      blueprints = blueprint_modules(Config.include_brando_blueprints?())

      {:ok,
       %{
         "server" => %{
           "name" => "brando_mcp",
           "version" => app_version(:brando_mcp),
           "writes_enabled" => Config.writes_enabled?()
         },
         "brando" => %{
           "version" => app_version(:brando),
           "otp_app" => runtime_value(:otp_app),
           "blueprint_count" => length(blueprints)
         },
         "limits" => %{
           "default_page_size" => Config.default_page_size(),
           "max_page_size" => Config.max_page_size(),
           "max_seed_batch_size" => Config.max_seed_batch_size(),
           "serializer_depth" => Config.serializer_depth()
         },
         "generation" => %{
           "seed_content" => "connected_mcp_client_llm",
           "translation" => "connected_mcp_client_llm",
           "server_side_llm" => false
         }
       }}
    end
  end

  @impl true
  def list_blueprints(params) do
    with :ok <- ensure_brando() do
      include_brando =
        Map.get(params, :include_brando, Map.get(params, "include_brando", false)) ||
          Config.include_brando_blueprints?()

      summaries =
        include_brando
        |> blueprint_modules()
        |> Enum.map(&blueprint_summary/1)
        |> Enum.sort_by(& &1["module"])

      {:ok, %{"blueprints" => summaries, "count" => length(summaries)}}
    end
  end

  @impl true
  def describe_blueprint(reference) do
    with {:ok, module} <- resolve_blueprint(reference) do
      naming = call(module, :__naming__, [])
      required_attrs = call_if_exported(module, :__required_attrs__, [], [])
      required_relations = call_if_exported(module, :__required_relations__, [], [])
      required_assets = call_if_exported(module, :__required_assets__, [], [])

      attributes =
        module
        |> metadata(:attributes)
        |> Enum.map(&entity_summary(&1, required_attrs))

      relations =
        module
        |> metadata(:relations)
        |> Enum.map(&entity_summary(&1, required_relations))

      assets =
        module
        |> metadata(:assets)
        |> Enum.map(&entity_summary(&1, required_assets))

      traits =
        module
        |> call_if_exported(:__traits__, [], [])
        |> Enum.map(fn
          {trait, opts} -> %{"module" => inspect(trait), "options" => opts}
          trait -> %{"module" => inspect(trait)}
        end)

      {:ok,
       %{
         "module" => inspect(module),
         "id" => map_value(naming, :id),
         "naming" => naming,
         "schema" => schema_summary(module),
         "attributes" => attributes,
         "relations" => relations,
         "assets" => assets,
         "traits" => traits,
         "forms" => forms_summary(module),
         "listings" => listings_summary(module)
       }}
    end
  end

  @impl true
  def list_entries(reference, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         {:ok, query_opts} <- list_query_opts(module, params),
         {:ok, result} <- context_call(module, :list, [query_opts]) do
      case result do
        %{entries: entries, pagination_meta: pagination} ->
          {:ok,
           %{
             "entries" => entries,
             "count" => length(entries),
             "pagination" => pagination,
             "blueprint" => blueprint_summary(module)
           }}

        entries when is_list(entries) ->
          {:ok,
           %{
             "entries" => entries,
             "count" => length(entries),
             "blueprint" => blueprint_summary(module)
           }}

        other ->
          {:error, {:unexpected_query_result, other}}
      end
    end
  end

  @impl true
  def get_entry(reference, id, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         {:ok, query_opts} <- single_query_opts(module, id, params),
         {:ok, entry} <- context_call(module, :get, [query_opts]) do
      {:ok, %{"entry" => entry, "blueprint" => blueprint_summary(module)}}
    end
  end

  @impl true
  def create_entry(reference, attrs, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         :ok <- ensure_write_allowed(module),
         {:ok, user} <- resolve_user(params),
         {:ok, entry} <-
           context_call(module, :create, [
             attrs,
             user,
             [notify?: false, pubsub?: false, cast_blocks: true]
           ]) do
      {:ok, %{"entry" => entry, "operation" => "created"}}
    end
  end

  @impl true
  def update_entry(reference, id, attrs, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         :ok <- ensure_write_allowed(module),
         {:ok, user} <- resolve_user(params),
         id <- coerce_id(module, id),
         {:ok, entry} <-
           context_call(module, :update, [
             id,
             attrs,
             user,
             [show_notification: false]
           ]) do
      {:ok, %{"entry" => entry, "operation" => "updated"}}
    end
  end

  @impl true
  def delete_entry(reference, id, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         :ok <- ensure_write_allowed(module),
         true <- Map.get(params, :confirm, Map.get(params, "confirm", false)),
         {:ok, user} <- resolve_user(params),
         id <- coerce_id(module, id),
         {:ok, entry} <- context_call(module, :delete, [id, user]) do
      {:ok, %{"entry" => entry, "operation" => "deleted"}}
    else
      false -> {:error, "delete_entry requires confirm=true"}
      error -> error
    end
  end

  @impl true
  def seed_contract(reference, params) do
    with {:ok, module} <- resolve_blueprint(reference) do
      requested_count = params |> value(:count, 1) |> clamp(1, Config.max_seed_batch_size())
      required_attrs = call_if_exported(module, :__required_attrs__, [], [])
      required_relations = call_if_exported(module, :__required_relations__, [], [])
      required_assets = call_if_exported(module, :__required_assets__, [], [])

      attributes =
        module
        |> metadata(:attributes)
        |> Enum.reject(&system_field?/1)
        |> Enum.map(&seed_field_contract(&1, required_attrs))

      relations =
        module
        |> metadata(:relations)
        |> Enum.reject(&(Map.get(&1, :opts, %{}) |> option(:module) == :blocks))
        |> Enum.map(&seed_relation_contract(&1, required_relations))

      assets =
        module
        |> metadata(:assets)
        |> Enum.map(&seed_asset_contract(&1, required_assets))

      block_fields =
        module
        |> call_if_exported(:__blocks_fields__, [], [])
        |> Enum.map(fn field -> seed_block_contract(module, field) end)

      attribute_properties =
        Map.new(attributes, fn field ->
          {to_string(field["name"]), Map.drop(field, ["name", "required"])}
        end)

      relation_properties =
        Map.new(relations, fn relation ->
          {relation["input"], relation_json_schema(relation)}
        end)

      asset_properties =
        Map.new(assets, fn asset ->
          {asset["input"], asset_json_schema(asset)}
        end)

      block_properties =
        Map.new(block_fields, fn block_field ->
          {block_field["input"], %{"type" => "array", "items" => %{"type" => "object"}}}
        end)

      properties =
        attribute_properties
        |> Map.merge(relation_properties)
        |> Map.merge(asset_properties)
        |> Map.merge(block_properties)

      required =
        Enum.flat_map(attributes, fn field ->
          if field["required"], do: [to_string(field["name"])], else: []
        end) ++
          Enum.flat_map(relations ++ assets, fn association ->
            if association["required"], do: [association["input"]], else: []
          end)

      {:ok,
       %{
         "blueprint" => blueprint_summary(module),
         "requested_count" => requested_count,
         "maximum_batch_size" => Config.max_seed_batch_size(),
         "defaults" => seed_defaults(module),
         "input_schema" => %{
           "type" => "object",
           "properties" => properties,
           "required" => required,
           "additionalProperties" => true
         },
         "attributes" => attributes,
         "relations" => relations,
         "assets" => assets,
         "block_fields" => block_fields,
         "entry_shape" => %{
           "ref" => "A unique batch-local handle, for example employee-ada.",
           "attributes" =>
             "Blueprint attributes. References to earlier entries may use {\"$ref\":\"handle\"}."
         },
         "instructions" => [
           "Generate complete, internally consistent entries and keep them as drafts unless the user explicitly requests publication.",
           "Call brando_validate_seed_batch and show its preview before brando_apply_seed_batch.",
           "For block fields, send Brando's nested entry_<field> block parameters; they are validated with cast_blocks=true.",
           "Use existing asset ids for image/file/gallery fields until an upload workflow supplies new asset ids."
         ]
       }}
    end
  end

  @impl true
  def validate_seed_batch(reference, entries, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         {:ok, user} <- resolve_preview_user(params),
         {:ok, normalized} <-
           Seed.normalize_entries(entries, seed_defaults(module), Config.max_seed_batch_size()),
         {:ok, previews} <- build_seed_previews(module, normalized, user) do
      valid? = Enum.all?(previews, & &1["valid"])

      {:ok,
       %{
         "blueprint" => blueprint_summary(module),
         "valid" => valid?,
         "count" => length(previews),
         "entries" => previews
       }}
    end
  end

  @impl true
  def apply_seed_batch(reference, entries, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         :ok <- ensure_write_allowed(module),
         :ok <- require_confirmation(params, "apply_seed_batch"),
         {:ok, user} <- resolve_user(params),
         {:ok, normalized} <-
           Seed.normalize_entries(entries, seed_defaults(module), Config.max_seed_batch_size()),
         {:ok, previews} <- build_seed_previews(module, normalized, user),
         :ok <- ensure_valid_seed_previews(previews) do
      transaction(fn ->
        Seed.apply_entries(normalized, fn attributes, _entry ->
          context_call(module, :create, [
            attributes,
            user,
            [notify?: false, pubsub?: false, cast_blocks: true]
          ])
        end)
      end)
      |> case do
        {:ok, created} ->
          {:ok,
           %{
             "operation" => "seeded",
             "blueprint" => blueprint_summary(module),
             "count" => length(created),
             "entries" => created
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def prepare_translation(reference, id, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         {:ok, target_language} <- target_language(module, value(params, :target_language)),
         {:ok, entry} <- translation_entry(module, id),
         {:ok, items} <- collect_translation_items(entry, module) do
      source_language = entry |> map_value(:language) |> normalize_language()

      manifest =
        Translation.manifest(items, %{
          "blueprint" => inspect(module),
          "entry_id" => map_value(entry, :id) || coerce_id(module, id),
          "source_language" => source_language,
          "target_language" => to_string(target_language)
        })

      {:ok,
       manifest
       |> Map.put("blueprint_summary", blueprint_summary(module))
       |> Map.put(
         "instructions",
         "Translate every item with the connected MCP client's LLM, then call brando_validate_translation before applying."
       )}
    end
  end

  @impl true
  def validate_translation(reference, id, translations, params) do
    with {:ok, manifest} <- prepare_translation(reference, id, params),
         {:ok, validation} <-
           Translation.validate(manifest, value(params, :source_digest), translations) do
      {:ok, Map.drop(validation, ["translations"])}
    end
  end

  @impl true
  def apply_translation(reference, id, translations, params) do
    with {:ok, module} <- resolve_blueprint(reference),
         :ok <- ensure_write_allowed(module),
         :ok <- require_confirmation(params, "apply_translation"),
         {:ok, user} <- resolve_user(params),
         {:ok, target_language} <- target_language(module, value(params, :target_language)),
         {:ok, manifest} <- prepare_translation(reference, id, params),
         {:ok, validation} <-
           Translation.validate(manifest, value(params, :source_digest), translations) do
      transaction(fn ->
        apply_translation_transaction(
          module,
          coerce_id(module, id),
          target_language,
          manifest,
          validation["translations"],
          user
        )
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp system_field?(entity) do
    Map.get(entity, :name) in @seed_system_fields
  end

  defp seed_field_contract(field, required_fields) do
    name = Map.get(field, :name)
    type = Map.get(field, :type)
    opts = Map.get(field, :opts, %{})

    type
    |> field_json_schema(opts)
    |> Map.merge(%{
      "name" => name,
      "brando_type" => type_name(type),
      "required" => name in required_fields,
      "options" => seed_options(opts)
    })
  end

  defp seed_relation_contract(relation, required_fields) do
    name = Map.get(relation, :name)
    type = Map.get(relation, :type)
    opts = Map.get(relation, :opts, %{})

    %{
      "name" => name,
      "type" => type_name(type),
      "required" => name in required_fields,
      "module" => option(opts, :module),
      "input" => association_input(relation),
      "reference_support" =>
        "A scalar foreign-key input may use {\"$ref\":\"batch-handle\"} to target another entry in this batch."
    }
  end

  defp seed_asset_contract(asset, required_fields) do
    name = Map.get(asset, :name)
    type = Map.get(asset, :type)

    %{
      "name" => name,
      "type" => type_name(type),
      "required" => name in required_fields,
      "input" => association_input(asset),
      "instructions" =>
        "Use an existing Brando media id. Uploading or generating media is a separate workflow."
    }
  end

  defp seed_block_contract(_module, field) do
    name = Map.get(field, :name)

    %{
      "name" => name,
      "input" => "entry_#{name}",
      "type" => "array",
      "required" => false,
      "instructions" =>
        "Supply Brando entry-block association parameters, including nested block data, refs, vars, and children."
    }
  end

  defp field_json_schema({:array, subtype}, opts) do
    %{
      "type" => "array",
      "items" => field_json_schema(subtype, opts)
    }
  end

  defp field_json_schema(type, _opts) when type in [:integer, :id], do: %{"type" => "integer"}
  defp field_json_schema(type, _opts) when type in [:float, :decimal], do: %{"type" => "number"}
  defp field_json_schema(:boolean, _opts), do: %{"type" => "boolean"}
  defp field_json_schema(:date, _opts), do: %{"type" => "string", "format" => "date"}

  defp field_json_schema(type, _opts)
       when type in [:datetime, :utc_datetime, :naive_datetime] do
    %{"type" => "string", "format" => "date-time"}
  end

  defp field_json_schema(type, _opts) when type in [:map, :json], do: %{"type" => "object"}

  defp field_json_schema(type, opts) when type in [:enum, :language, :status] do
    enum_values =
      option(opts, :values) || option(opts, :options) || option(opts, :allowed_values)

    %{"type" => "string"}
    |> put_if_present("enum", normalize_enum_values(enum_values))
  end

  defp field_json_schema(_type, _opts), do: %{"type" => "string"}

  defp normalize_enum_values(nil), do: nil

  defp normalize_enum_values(values) when is_list(values) do
    Enum.map(values, fn
      {label, value} when is_binary(label) -> to_string(value)
      {value, _label} -> to_string(value)
      value -> to_string(value)
    end)
  end

  defp normalize_enum_values(_values), do: nil

  defp seed_options(opts) when is_map(opts) do
    opts
    |> Map.drop([:module])
    |> BrandoMCP.JSON.normalize()
  end

  defp seed_options(opts) when is_list(opts) do
    opts
    |> Enum.reject(fn {key, _value} -> key == :module end)
    |> Map.new()
    |> BrandoMCP.JSON.normalize()
  end

  defp seed_options(_opts), do: %{}

  defp association_input(%{type: type, name: name} = association)
       when type in [:belongs_to, :image, :file, :video] do
    if exported?(@association_key, :for, 1) do
      association |> then(&apply(@association_key, :for, [&1])) |> to_string()
    else
      "#{name}_id"
    end
  end

  defp association_input(%{name: name}), do: to_string(name)

  defp relation_json_schema(%{"type" => type})
       when type in ["belongs_to", "belongs_to_required"] do
    %{
      "oneOf" => [
        %{"type" => "integer"},
        %{"type" => "string"},
        %{
          "type" => "object",
          "properties" => %{"$ref" => %{"type" => "string"}},
          "required" => ["$ref"],
          "additionalProperties" => false
        }
      ]
    }
  end

  defp relation_json_schema(%{"type" => type})
       when type in ["has_many", "many_to_many", "entries", "embeds_many"] do
    %{"type" => "array"}
  end

  defp relation_json_schema(_relation), do: %{"type" => "object"}

  defp asset_json_schema(%{"type" => type}) when type in ["image", "file", "video"] do
    %{"oneOf" => [%{"type" => "integer"}, %{"type" => "string"}]}
  end

  defp asset_json_schema(%{"type" => "gallery"}), do: %{"type" => "object"}
  defp asset_json_schema(_asset), do: %{"type" => "object"}

  defp seed_defaults(module) do
    factory = call_if_exported(module, :__factory__, [%{}], %{})

    form_defaults =
      case call_if_exported(module, :__form__, [], nil) do
        %{default_params: defaults} when is_map(defaults) -> defaults
        _other -> %{}
      end

    factory
    |> stringify_keys()
    |> Map.merge(stringify_keys(form_defaults))
    |> maybe_default_draft(module)
  end

  defp maybe_default_draft(defaults, module) do
    if :status in schema_values(module, :fields) do
      Map.put_new(defaults, "status", "draft")
    else
      defaults
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, val} -> {to_string(key), val} end)
  end

  defp stringify_keys(_value), do: %{}

  defp resolve_preview_user(%{__brando_actor__: actor}) when not is_nil(actor), do: {:ok, actor}

  defp resolve_preview_user(params) do
    if is_nil(value(params, :user_id)) do
      {:ok, Config.user() || :system}
    else
      resolve_user(params)
    end
  end

  defp build_seed_previews(module, entries, user) do
    if exported?(module, :changeset, 5) do
      previews =
        Enum.map(entries, fn entry ->
          attributes = Seed.preview_attributes(entry.attributes)

          changeset =
            apply(module, :changeset, [
              struct(module),
              attributes,
              user,
              nil,
              [cast_blocks: true]
            ])

          Seed.preview(changeset, entry, missing_required(module, entry.attributes))
        end)

      {:ok, previews}
    else
      {:error, {:changeset_not_available, inspect(module)}}
    end
  rescue
    exception -> {:error, {:seed_validation_failed, Exception.message(exception)}}
  end

  defp missing_required(module, attributes) do
    required_attrs = call_if_exported(module, :__required_attrs__, [], [])
    required_relations = call_if_exported(module, :__required_relations__, [], [])
    required_assets = call_if_exported(module, :__required_assets__, [], [])

    required_relation_inputs =
      module
      |> metadata(:relations)
      |> Enum.filter(&(Map.get(&1, :name) in required_relations))
      |> Enum.map(&association_input/1)

    required_asset_inputs =
      module
      |> metadata(:assets)
      |> Enum.filter(&(Map.get(&1, :name) in required_assets))
      |> Enum.map(&association_input/1)

    required = required_attrs ++ required_relation_inputs ++ required_asset_inputs

    Enum.filter(required, fn field ->
      case map_value(attributes, field) do
        nil -> true
        "" -> true
        [] -> true
        _value -> false
      end
    end)
  end

  defp require_confirmation(params, operation) do
    if value(params, :confirm, false) == true do
      :ok
    else
      {:error, "#{operation} requires confirm=true"}
    end
  end

  defp ensure_valid_seed_previews(previews) do
    if Enum.all?(previews, & &1["valid"]) do
      :ok
    else
      {:error, "seed batch is invalid; run brando_validate_seed_batch and fix its errors"}
    end
  end

  defp target_language(module, language) when is_atom(language) do
    validate_target_language_field(module, language)
  end

  defp target_language(module, language) when is_binary(language) and language != "" do
    case existing_atom(language) do
      {:ok, atom} -> validate_target_language_field(module, atom)
      :error -> {:error, {:unknown_target_language, language}}
    end
  end

  defp target_language(_module, _language),
    do: {:error, "target_language must be a configured language code"}

  defp validate_target_language_field(module, language) do
    if :language in schema_values(module, :fields) do
      {:ok, language}
    else
      {:error, {:blueprint_is_not_translatable, inspect(module)}}
    end
  end

  defp translation_entry(module, id) do
    preloads = call_if_exported(@blueprint, :preloads_for, [module], [])

    context_call(module, :get, [
      %{
        matches: %{id: coerce_id(module, id)},
        preload: preloads
      }
    ])
  end

  defp collect_translation_items(entry, module) do
    service = Config.translation_content_adapter()

    if exported?(service, :collect_translatable_content, 2) do
      case apply(service, :collect_translatable_content, [entry, module]) do
        items when is_list(items) -> {:ok, items}
        other -> {:error, {:unexpected_translation_content, other}}
      end
    else
      {:error, {:translation_content_adapter_not_available, inspect(service)}}
    end
  end

  defp normalize_language(nil), do: nil
  defp normalize_language(language), do: to_string(language)

  defp apply_translation_transaction(
         module,
         source_id,
         target_language,
         manifest,
         translated_texts,
         user
       ) do
    with {:ok, source_entry} <- translation_entry(module, source_id),
         {:ok, source_items} <- collect_translation_items(source_entry, module),
         fresh_manifest <-
           translation_manifest(module, source_entry, source_id, target_language, source_items),
         :ok <- ensure_fresh_source(manifest, fresh_manifest),
         {:ok, duplicated_entry} <-
           duplicate_translation_entry(module, source_id, target_language, user),
         :ok <- link_alternates(module, source_id, map_value(duplicated_entry, :id)),
         {:ok, target_entry} <- translation_entry(module, map_value(duplicated_entry, :id)),
         {:ok, target_items} <- collect_translation_items(target_entry, module),
         :ok <- ensure_translation_shapes(source_items, target_items),
         translated_items <-
           Enum.zip_with(target_items, translated_texts, &Translation.apply_text/2),
         :ok <- apply_translated_items(translated_items, target_entry, module),
         {:ok, translated_entry} <- translation_entry(module, map_value(target_entry, :id)),
         {:ok, final_entry} <- regenerate_slugs(module, translated_entry, user),
         :ok <- render_translated_entry(module, map_value(final_entry, :id)) do
      {:ok,
       %{
         "operation" => "translated",
         "blueprint" => blueprint_summary(module),
         "source_entry_id" => source_id,
         "target_entry_id" => map_value(final_entry, :id),
         "target_language" => to_string(target_language),
         "translated_items" => length(translated_items),
         "entry" => final_entry
       }}
    end
  end

  defp translation_manifest(module, entry, entry_id, target_language, items) do
    Translation.manifest(items, %{
      "blueprint" => inspect(module),
      "entry_id" => map_value(entry, :id) || entry_id,
      "source_language" => entry |> map_value(:language) |> normalize_language(),
      "target_language" => to_string(target_language)
    })
  end

  defp ensure_fresh_source(original, fresh) do
    if original["source_digest"] == fresh["source_digest"] do
      :ok
    else
      {:error, "source content changed after translation was prepared; prepare it again"}
    end
  end

  defp duplicate_translation_entry(module, source_id, target_language, user) do
    naming = call(module, :__naming__, [])
    context = module |> call(:__modules__, []) |> map_value(:context)
    operation = :"duplicate_#{map_value(naming, :singular)}"

    slug_changes =
      module
      |> call_if_exported(:__slug_fields__, [], [])
      |> Enum.map(fn slug_field ->
        {Map.get(slug_field, :name),
         fn _entry, current_value ->
           slugify("#{current_value}-#{target_language}")
         end}
      end)

    opts = [change_fields: [{:language, target_language} | slug_changes]]

    if is_atom(context) and exported?(context, operation, 3) do
      normalize_context_result(apply(context, operation, [source_id, user, opts]))
    else
      {:error, {:context_function_not_available, "#{inspect(context)}.#{operation}/3"}}
    end
  end

  defp link_alternates(module, source_id, target_id) do
    alternates? = call_if_exported(module, :has_alternates?, [], false)
    alternate_module = Module.concat(module, "Alternate")

    cond do
      not alternates? ->
        :ok

      is_nil(target_id) ->
        {:error, :duplicated_translation_has_no_id}

      exported?(alternate_module, :add, 2) ->
        case apply(alternate_module, :add, [source_id, target_id]) do
          :ok -> :ok
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_alternate_result, other}}
        end

      true ->
        {:error, {:alternate_linker_not_available, inspect(alternate_module)}}
    end
  end

  defp ensure_translation_shapes(source_items, target_items) do
    if Translation.compatible_shapes?(source_items, target_items) do
      :ok
    else
      {:error,
       "the duplicated entry has a different translatable content shape; no translations were applied"}
    end
  end

  defp apply_translated_items(translated_items, target_entry, module) do
    service = Config.translation_content_adapter()

    if exported?(service, :apply_translations, 3) do
      case apply(service, :apply_translations, [translated_items, target_entry, module]) do
        :ok -> :ok
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_translation_apply_result, other}}
      end
    else
      {:error, {:translation_content_adapter_not_available, inspect(service)}}
    end
  end

  defp regenerate_slugs(module, entry, user) do
    slug_changes =
      module
      |> call_if_exported(:__slug_fields__, [], [])
      |> Enum.reduce(%{}, fn slug_field, changes ->
        name = Map.get(slug_field, :name)

        case slug_source(module, name) do
          nil ->
            changes

          fields when is_list(fields) ->
            value =
              fields
              |> Enum.map_join("-", &(map_value(entry, &1) || ""))
              |> slugify()

            maybe_put_slug(changes, name, value)

          field ->
            value = entry |> map_value(field) |> to_string_or_empty() |> slugify()
            maybe_put_slug(changes, name, value)
        end
      end)

    if map_size(slug_changes) == 0 do
      {:ok, entry}
    else
      context_call(module, :update, [
        map_value(entry, :id),
        slug_changes,
        user,
        [show_notification: false]
      ])
    end
  end

  defp slug_source(module, slug_name) do
    module
    |> call_if_exported(:__form__, [], nil)
    |> find_slug_source(slug_name)
  end

  defp find_slug_source(%{} = value, slug_name) do
    if map_value(value, :name) == slug_name and map_value(value, :type) == :slug do
      value |> map_value(:opts) |> option(:source)
    else
      value
      |> Map.values()
      |> Enum.find_value(&find_slug_source(&1, slug_name))
    end
  end

  defp find_slug_source(value, slug_name) when is_list(value) do
    Enum.find_value(value, &find_slug_source(&1, slug_name))
  end

  defp find_slug_source(_value, _slug_name), do: nil

  defp maybe_put_slug(changes, _name, ""), do: changes
  defp maybe_put_slug(changes, name, value), do: Map.put(changes, name, value)

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value), do: to_string(value)

  defp slugify(value) do
    if exported?(@utils, :slugify, 1) do
      apply(@utils, :slugify, [value])
    else
      value
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
      |> String.trim("-")
    end
  end

  defp render_translated_entry(module, id) do
    if call_if_exported(module, :__blocks_fields__, [], []) != [] and
         exported?(@content_blocks, :render_entry, 2) do
      case apply(@content_blocks, :render_entry, [module, id]) do
        {:ok, _entry} -> :ok
        :ok -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_render_result, other}}
      end
    else
      :ok
    end
  end

  defp transaction(fun) when is_function(fun, 0) do
    repo = Config.repo()

    if exported?(repo, :transaction, 1) and exported?(repo, :rollback, 1) do
      case apply(repo, :transaction, [
             fn ->
               case fun.() do
                 {:ok, result} -> result
                 {:error, reason} -> apply(repo, :rollback, [reason])
               end
             end
           ]) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_transaction_result, other}}
      end
    else
      fun.()
    end
  end

  defp normalize_context_result({:ok, result}), do: {:ok, result}
  defp normalize_context_result({:error, reason}), do: {:error, reason}
  defp normalize_context_result(other), do: {:error, {:unexpected_context_result, other}}

  defp option(opts, key) when is_map(opts),
    do: Map.get(opts, key, Map.get(opts, Atom.to_string(key)))

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp option(_opts, _key), do: nil

  defp ensure_brando do
    if Code.ensure_loaded?(@blueprint) or is_list(Config.blueprints()) do
      :ok
    else
      {:error,
       "Brando is not loaded. Run this server from a started Brando application (for example with mix brando.mcp)."}
    end
  end

  defp blueprint_modules(include_brando) do
    modules =
      case Config.blueprints() do
        modules when is_list(modules) ->
          modules

        _ ->
          cond do
            include_brando and exported?(@blueprint, :list_blueprints, 1) ->
              apply(@blueprint, :list_blueprints, [:include_brando])

            exported?(@blueprint, :list_blueprints, 0) ->
              apply(@blueprint, :list_blueprints, [])

            true ->
              []
          end
      end

    modules
    |> Enum.filter(&blueprint?/1)
    |> Enum.uniq()
  end

  defp blueprint?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__blueprint__, 0)
  end

  defp blueprint?(_module), do: false

  defp resolve_blueprint(reference) when is_binary(reference) do
    matches =
      true
      |> blueprint_modules()
      |> Enum.filter(fn module ->
        reference in blueprint_references(module) or
          String.downcase(reference) in Enum.map(blueprint_references(module), &String.downcase/1)
      end)

    case matches do
      [module] -> {:ok, module}
      [] -> {:error, {:blueprint_not_found, reference}}
      modules -> {:error, {:ambiguous_blueprint, Enum.map(modules, &inspect/1)}}
    end
  end

  defp resolve_blueprint(reference) when is_atom(reference) do
    if reference in blueprint_modules(true) do
      {:ok, reference}
    else
      {:error, {:blueprint_not_found, inspect(reference)}}
    end
  end

  defp blueprint_references(module) do
    naming = call(module, :__naming__, [])

    [
      inspect(module),
      map_value(naming, :id),
      map_value(naming, :singular),
      map_value(naming, :plural),
      map_value(naming, :schema)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp blueprint_summary(module) do
    naming = call(module, :__naming__, [])

    %{
      "module" => inspect(module),
      "id" => map_value(naming, :id),
      "application" => map_value(naming, :application),
      "domain" => map_value(naming, :domain),
      "schema" => map_value(naming, :schema),
      "singular" => map_value(naming, :singular),
      "plural" => map_value(naming, :plural),
      "table" => map_value(naming, :table_name)
    }
  end

  defp metadata(module, kind) do
    local_function = :"__#{kind}__"

    cond do
      exported?(module, local_function, 0) ->
        apply(module, local_function, [])

      kind == :attributes and exported?(@attributes, :__attributes__, 1) ->
        apply(@attributes, :__attributes__, [module])

      kind == :relations and exported?(@relations, :__relations__, 1) ->
        apply(@relations, :__relations__, [module])

      kind == :assets and exported?(@assets, :__assets__, 1) ->
        apply(@assets, :__assets__, [module])

      true ->
        []
    end
  end

  defp entity_summary(entity, required) do
    name = Map.get(entity, :name)

    %{
      "name" => name,
      "type" => type_name(Map.get(entity, :type)),
      "required" => name in required,
      "options" => Map.get(entity, :opts, %{})
    }
  end

  defp schema_summary(module) do
    fields = schema_values(module, :fields)

    %{
      "primary_key" => schema_values(module, :primary_key),
      "fields" =>
        Enum.map(fields, fn field ->
          %{"name" => field, "type" => type_name(schema_value(module, :type, field))}
        end),
      "associations" => schema_values(module, :associations),
      "embeds" => schema_values(module, :embeds)
    }
  end

  defp forms_summary(module) do
    module
    |> call_if_exported(:__forms__, [], [])
    |> Enum.map(fn form ->
      fields =
        if exported?(@forms, :list_fields, 1) do
          apply(@forms, :list_fields, [form])
        else
          Map.get(form, :fields, [])
        end

      %{
        "name" => Map.get(form, :name),
        "default_params" => Map.get(form, :default_params, %{}),
        "fields" => fields,
        "block_fields" =>
          form
          |> Map.get(:blocks, [])
          |> Enum.map(&Map.get(&1, :name))
      }
    end)
  end

  defp listings_summary(module) do
    module
    |> call_if_exported(:__listings__, [], [])
    |> Enum.map(fn listing ->
      %{
        "name" => Map.get(listing, :name),
        "query" => Map.get(listing, :query, %{}),
        "limit" => Map.get(listing, :limit),
        "sortable" => Map.get(listing, :sortable),
        "filters" =>
          listing
          |> Map.get(:filters, [])
          |> Enum.map(&Map.take(&1, [:key, :label, :type, :default])),
        "sorts" =>
          listing
          |> Map.get(:sorts, [])
          |> Enum.map(&Map.take(&1, [:key, :label, :order]))
      }
    end)
  end

  defp list_query_opts(module, params) do
    limit =
      params
      |> value(:limit, Config.default_page_size())
      |> clamp(1, Config.max_page_size())

    offset = params |> value(:offset, 0) |> clamp(0, 2_147_483_647)

    with {:ok, filter} <- normalize_filter(value(params, :filter), module),
         {:ok, fields} <- normalize_fields(value(params, :fields), module),
         {:ok, preloads} <- normalize_preloads(value(params, :preload), module),
         {:ok, order} <- normalize_order(value(params, :order)) do
      opts =
        %{
          limit: limit,
          offset: offset,
          paginate: true
        }
        |> put_if_present(:filter, filter)
        |> put_if_present(:select, fields)
        |> put_if_present(:preload, preloads)
        |> put_if_present(:order, order)
        |> put_if_present(:status, value(params, :status))
        |> put_if_present(:language, value(params, :language))
        |> put_if_present(:with_deleted, enabled_option(params, :with_deleted))

      {:ok, opts}
    end
  end

  defp single_query_opts(module, id, params) do
    with {:ok, fields} <- normalize_fields(value(params, :fields), module),
         {:ok, preloads} <- normalize_preloads(value(params, :preload), module) do
      opts =
        %{matches: %{id: coerce_id(module, id)}}
        |> put_if_present(:select, fields)
        |> put_if_present(:preload, preloads)
        |> put_if_present(:with_deleted, enabled_option(params, :with_deleted))
        |> put_if_present(:revision, value(params, :revision))

      {:ok, opts}
    end
  end

  defp normalize_filter(nil, _module), do: {:ok, nil}

  defp normalize_filter(filter, _module) when is_map(filter) do
    Enum.reduce_while(filter, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case existing_atom(key) do
        {:ok, atom} -> {:cont, {:ok, Map.put(acc, atom, value)}}
        :error -> {:halt, {:error, {:unknown_filter, key}}}
      end
    end)
  end

  defp normalize_filter(_filter, _module), do: {:error, "filter must be an object"}

  defp normalize_fields(nil, _module), do: {:ok, nil}

  defp normalize_fields(fields, module) when is_list(fields) do
    normalize_schema_names(fields, schema_values(module, :fields), :field)
  end

  defp normalize_fields(_fields, _module), do: {:error, "fields must be an array of field names"}

  defp normalize_preloads(nil, _module), do: {:ok, nil}

  defp normalize_preloads(preloads, module) when is_list(preloads) do
    valid = schema_values(module, :associations) ++ schema_values(module, :embeds)
    normalize_schema_names(preloads, valid, :preload)
  end

  defp normalize_preloads(_preloads, _module),
    do: {:error, "preload must be an array of association names"}

  defp normalize_schema_names(requested, valid, kind) do
    by_name = Map.new(valid, &{to_string(&1), &1})

    Enum.reduce_while(requested, {:ok, []}, fn name, {:ok, acc} ->
      case Map.fetch(by_name, to_string(name)) do
        {:ok, atom} -> {:cont, {:ok, [atom | acc]}}
        :error -> {:halt, {:error, {:"unknown_#{kind}", name}}}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      error -> error
    end
  end

  defp normalize_order(nil), do: {:ok, nil}

  defp normalize_order(order) when is_binary(order) do
    valid? =
      order
      |> String.split(",", trim: true)
      |> Enum.all?(fn expression ->
        case String.split(String.trim(expression), ~r/\s+/, trim: true) do
          [direction, path]
          when direction in ~w(asc desc asc_nulls_first asc_nulls_last desc_nulls_first desc_nulls_last) ->
            path
            |> String.split(".")
            |> Enum.all?(fn segment -> existing_atom(segment) != :error end)

          _ ->
            false
        end
      end)

    if valid?, do: {:ok, order}, else: {:error, {:invalid_order, order}}
  end

  defp normalize_order(_order), do: {:error, "order must be a Brando order string"}

  defp context_call(module, operation, args) do
    naming = call(module, :__naming__, [])
    modules = call(module, :__modules__, [])
    context = map_value(modules, :context)
    name = operation_name(operation, naming)

    if is_atom(context) and exported?(context, name, length(args)) do
      case apply(context, name, args) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_context_result, other}}
      end
    else
      {:error, {:context_function_not_available, "#{inspect(context)}.#{name}/#{length(args)}"}}
    end
  end

  defp operation_name(:list, naming), do: :"list_#{map_value(naming, :plural)}"
  defp operation_name(:get, naming), do: :"get_#{map_value(naming, :singular)}"
  defp operation_name(:create, naming), do: :"create_#{map_value(naming, :singular)}"
  defp operation_name(:update, naming), do: :"update_#{map_value(naming, :singular)}"
  defp operation_name(:delete, naming), do: :"delete_#{map_value(naming, :singular)}"

  defp ensure_write_allowed(module) do
    cond do
      not Config.writes_enabled?() ->
        {:error,
         "BrandoMCP writes are disabled. Set config :brando_mcp, writes_enabled: true to enable them."}

      not writable_blueprint?(module) ->
        {:error, {:blueprint_not_writable, inspect(module)}}

      true ->
        :ok
    end
  end

  defp writable_blueprint?(module) do
    case Config.writable_blueprints() do
      :all ->
        true

      configured ->
        allowed = List.wrap(configured)
        refs = blueprint_references(module)

        Enum.any?(allowed, fn
          ^module -> true
          ref when is_binary(ref) -> ref in refs
          _ -> false
        end)
    end
  end

  defp resolve_user(%{__brando_actor__: actor}) when not is_nil(actor), do: {:ok, actor}

  defp resolve_user(params) do
    configured_user = Config.user()
    user_id = value(params, :user_id)

    cond do
      not is_nil(user_id) ->
        run_user_resolver(user_id)

      not is_nil(configured_user) ->
        {:ok, configured_user}

      true ->
        {:error,
         "A Brando user is required for writes. Pass user_id or configure config :brando_mcp, user: user."}
    end
  end

  defp run_user_resolver(user_id) do
    resolver = Config.user_resolver()

    result =
      case resolver do
        function when is_function(function, 1) ->
          function.(user_id)

        {module, function} ->
          apply(module, function, [user_id])

        {module, function, extra_args} when is_list(extra_args) ->
          apply(module, function, [user_id | extra_args])

        nil ->
          if exported?(@users, :get_user, 1) do
            apply(@users, :get_user, [coerce_user_id(user_id)])
          else
            {:error, :user_resolver_not_configured}
          end
      end

    case result do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
      nil -> {:error, {:user_not_found, user_id}}
      user -> {:ok, user}
    end
  end

  defp coerce_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _ -> id
    end
  end

  defp coerce_user_id(id), do: id

  defp coerce_id(module, id) when is_binary(id) do
    case schema_value(module, :type, :id) do
      type when type in [:id, :integer] ->
        case Integer.parse(id) do
          {integer, ""} -> integer
          _ -> id
        end

      _ ->
        id
    end
  end

  defp coerce_id(_module, id), do: id

  defp schema_values(module, selector) do
    if exported?(module, :__schema__, 1) do
      apply(module, :__schema__, [selector]) || []
    else
      []
    end
  end

  defp schema_value(module, selector, field) do
    if exported?(module, :__schema__, 2) do
      apply(module, :__schema__, [selector, field])
    end
  end

  defp runtime_value(key) do
    call_if_exported(@runtime_config, :get, [key], nil)
  end

  defp app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> nil
      version -> to_string(version)
    end
  end

  defp type_name(type) when is_atom(type), do: Atom.to_string(type)
  defp type_name(type), do: inspect(type)

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp enabled_option(map, key) do
    case value(map, key) do
      true -> true
      "true" -> true
      :only -> :only
      "only" -> :only
      _ -> nil
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case existing_atom(key) do
          {:ok, atom} -> Map.get(map, atom)
          :error -> nil
        end
    end
  end

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp call(module, function, args), do: apply(module, function, args)

  defp call_if_exported(module, function, args, default) do
    if exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      default
    end
  end

  defp exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp existing_atom(value) when is_atom(value), do: {:ok, value}

  defp existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp existing_atom(_value), do: :error

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp clamp(value, minimum, maximum) when is_integer(value) do
    value |> max(minimum) |> min(maximum)
  end

  defp clamp(_value, minimum, _maximum), do: minimum
end
