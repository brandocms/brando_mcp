defmodule BrandoMCP.BrandoTest do
  use ExUnit.Case, async: false

  alias BrandoMCP.Brando
  alias BrandoMCP.Test.FakeBlueprint

  setup do
    original = Application.get_all_env(:brando_mcp)

    Application.put_env(:brando_mcp, :blueprints, [FakeBlueprint])

    Application.put_env(
      :brando_mcp,
      :translation_content_adapter,
      BrandoMCP.Test.FakeTranslation
    )

    Application.put_env(:brando_mcp, :test_pid, self())
    Application.delete_env(:brando_mcp, :writes_enabled)
    Application.delete_env(:brando_mcp, :user)
    Application.delete_env(:brando_mcp, :user_resolver)

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

  test "lists and describes compiled blueprints" do
    assert {:ok, %{"count" => 1, "blueprints" => [summary]}} =
             Brando.list_blueprints(%{})

    assert summary["module"] == "BrandoMCP.Test.FakeBlueprint"
    assert summary["id"] == "demo-content-article"

    assert {:ok, description} = Brando.describe_blueprint("articles")
    assert description["schema"]["primary_key"] == [:id]
    assert [%{"name" => :title, "required" => true} | _] = description["attributes"]
    assert [%{"name" => :author, "required" => true}] = description["relations"]
    assert [%{"name" => :cover, "type" => "image"}] = description["assets"]
  end

  test "lists entries with bounded, normalized query options" do
    Application.put_env(:brando_mcp, :max_page_size, 50)

    assert {:ok, %{"count" => 1, "entries" => [entry]}} =
             Brando.list_entries("demo-content-article", %{
               "filter" => %{"title" => "First"},
               "fields" => ["id", "title"],
               "preload" => ["author"],
               "limit" => 500,
               "offset" => 10,
               "order" => "asc title"
             })

    assert entry.title == "First"

    assert_receive {:list_articles, opts}
    assert opts.limit == 50
    assert opts.offset == 10
    assert opts.filter == %{title: "First"}
    assert opts.select == [:id, :title]
    assert opts.preload == [:author]
    assert opts.paginate
    refute Map.has_key?(opts, :with_deleted)
  end

  test "gets integer primary keys without creating atoms from input" do
    assert {:ok, %{"entry" => %{id: 12}}} =
             Brando.get_entry("BrandoMCP.Test.FakeBlueprint", "12", %{})

    assert_receive {:get_article, %{matches: %{id: 12}}}

    assert {:error, {:unknown_filter, "not_a_loaded_atom"}} =
             Brando.list_entries("articles", %{"filter" => %{"not_a_loaded_atom" => "x"}})
  end

  test "writes are disabled by default" do
    assert {:error, message} =
             Brando.create_entry("articles", %{"title" => "New"}, %{user_id: 7})

    assert message =~ "writes are disabled"
    refute_received {:create_article, _, _, _}
  end

  test "enabled writes use the configured Brando user" do
    user = %{id: 7, name: "Editor"}
    Application.put_env(:brando_mcp, :writes_enabled, true)
    Application.put_env(:brando_mcp, :user, user)

    assert {:ok, %{"operation" => "created", "entry" => %{"title" => "New"}}} =
             Brando.create_entry("articles", %{"title" => "New"}, %{})

    assert_receive {:create_article, %{"title" => "New"}, ^user,
                    [notify?: false, pubsub?: false, cast_blocks: true]}
  end

  test "an in-process call writes as the host's actor, not a user_id argument or the configured user" do
    actor = %{id: 3, name: "Signed in"}
    Application.put_env(:brando_mcp, :writes_enabled, true)
    Application.put_env(:brando_mcp, :user, %{id: 7, name: "Configured"})

    assert {:ok, %{isError: nil}} =
             "brando_create_entry"
             |> BrandoMCP.Embedded.call_tool(
               %{"blueprint" => "articles", "attributes" => %{"title" => "New"}, "user_id" => 7},
               actor
             )
             |> then(fn {:ok, result} -> {:ok, Map.put_new(result, :isError, nil)} end)

    assert_receive {:create_article, %{"title" => "New"}, ^actor, _opts}
  end

  test "delete requires confirmation even when writes are enabled" do
    Application.put_env(:brando_mcp, :writes_enabled, true)
    Application.put_env(:brando_mcp, :user, :system)

    assert {:error, "delete_entry requires confirm=true"} =
             Brando.delete_entry("articles", 1, %{})

    assert {:ok, %{"operation" => "deleted"}} =
             Brando.delete_entry("articles", 1, %{confirm: true})

    assert_receive {:delete_article, 1, :system}
  end

  test "describes and validates an LLM seed contract" do
    assert {:ok, contract} = Brando.seed_contract("articles", %{"count" => 3})
    assert contract["requested_count"] == 3
    assert contract["defaults"]["status"] == "draft"
    assert contract["defaults"]["language"] == :en
    assert contract["input_schema"]["required"] == ["title", "author_id"]

    assert {:ok, preview} =
             Brando.validate_seed_batch(
               "articles",
               [
                 %{
                   "ref" => "article-one",
                   "attributes" => %{
                     "title" => "A considered title",
                     "body" => "Useful body copy",
                     "author_id" => 7
                   }
                 }
               ],
               %{}
             )

    assert preview["valid"]
    assert [%{"ref" => "article-one", "valid" => true}] = preview["entries"]

    assert {:ok, invalid_preview} =
             Brando.validate_seed_batch("articles", [%{"attributes" => %{}}], %{})

    refute invalid_preview["valid"]
    assert [%{"errors" => %{"title" => ["can't be blank"]}}] = invalid_preview["entries"]
  end

  test "applies a confirmed seed batch through the generated context" do
    user = %{id: 7}
    Application.put_env(:brando_mcp, :writes_enabled, true)
    Application.put_env(:brando_mcp, :user, user)

    entries = [
      %{
        "ref" => "article-one",
        "attributes" => %{"title" => "Seeded", "author_id" => 7}
      }
    ]

    assert {:error, "apply_seed_batch requires confirm=true"} =
             Brando.apply_seed_batch("articles", entries, %{})

    assert {:ok, %{"operation" => "seeded", "count" => 1}} =
             Brando.apply_seed_batch("articles", entries, %{confirm: true})

    assert_receive {:create_article, attrs, ^user,
                    [notify?: false, pubsub?: false, cast_blocks: true]}

    assert attrs["title"] == "Seeded"
    assert attrs["status"] == "draft"
  end

  test "prepares, validates, and applies a client-generated translation" do
    user = %{id: 7}
    Application.put_env(:brando_mcp, :writes_enabled, true)
    Application.put_env(:brando_mcp, :user, user)

    assert {:ok, manifest} =
             Brando.prepare_translation("articles", 1, %{target_language: "no"})

    assert manifest["count"] == 2
    assert manifest["source_language"] == "en"
    assert manifest["target_language"] == "no"

    translations =
      Enum.map(manifest["items"], fn item ->
        translated =
          case {item["kind"], item["source"]} do
            {"field", "First"} -> "Første"
            {"field", _source} -> "<p>Hei {{ name }}</p>"
          end

        %{"key" => item["key"], "translation" => translated}
      end)

    params = %{
      target_language: "no",
      source_digest: manifest["source_digest"]
    }

    assert {:ok, %{"valid" => true, "count" => 2}} =
             Brando.validate_translation("articles", 1, translations, params)

    assert {:error, "apply_translation requires confirm=true"} =
             Brando.apply_translation("articles", 1, translations, params)

    assert {:ok,
            %{
              "operation" => "translated",
              "target_entry_id" => 99,
              "translated_items" => 2
            }} =
             Brando.apply_translation(
               "articles",
               1,
               translations,
               Map.put(params, :confirm, true)
             )

    assert_receive {:duplicate_article, 1, ^user, duplicate_opts}
    assert {:language, :no} in Keyword.fetch!(duplicate_opts, :change_fields)

    assert_receive {:apply_translations, translated_items, %{id: 99}, FakeBlueprint}

    assert [{:field, :title, "Første"}, {:field, :body, "<p>Hei {{ name }}</p>"}] =
             translated_items
  end
end
