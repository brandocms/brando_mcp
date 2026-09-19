defmodule BrandoMCP.TranslationTest do
  use ExUnit.Case, async: true

  alias BrandoMCP.Translation

  test "builds stable translation units and accepts preserved markup" do
    manifest =
      Translation.manifest(
        [
          {:field, :title, "Welcome"},
          {:field, :body, ~s(<p class="lead">Hello {{ name }}</p>)}
        ],
        %{
          "blueprint" => "Demo.Article",
          "entry_id" => 1,
          "source_language" => "en",
          "target_language" => "no"
        }
      )

    assert manifest["count"] == 2
    assert is_binary(manifest["source_digest"])
    assert [title, body] = manifest["items"]
    assert title["format"] == "plain_text"
    assert body["format"] == "html"

    translations = [
      %{"key" => title["key"], "translation" => "Velkommen"},
      %{
        "key" => body["key"],
        "translation" => ~s(<p class="lead">Hei {{ name }}</p>)
      }
    ]

    assert {:ok, %{"valid" => true, "translations" => ["Velkommen", _body]}} =
             Translation.validate(manifest, manifest["source_digest"], translations)
  end

  test "rejects stale sources and changed HTML or placeholders" do
    manifest =
      Translation.manifest(
        [{:field, :body, ~s(<p class="lead">Hello {{ name }}</p>)}],
        %{
          "blueprint" => "Demo.Article",
          "entry_id" => 1,
          "source_language" => "en",
          "target_language" => "no"
        }
      )

    [unit] = manifest["items"]

    assert {:error, %{"errors" => stale_errors}} =
             Translation.validate(
               manifest,
               "stale",
               [%{"key" => unit["key"], "translation" => unit["source"]}]
             )

    assert Enum.any?(stale_errors, &(&1["code"] == "source_changed"))

    assert {:error, %{"errors" => content_errors}} =
             Translation.validate(
               manifest,
               manifest["source_digest"],
               [
                 %{
                   "key" => unit["key"],
                   "translation" => "<div>Hei {{ person }}</div>"
                 }
               ]
             )

    assert Enum.any?(content_errors, &(&1["code"] == "html_changed"))
    assert Enum.any?(content_errors, &(&1["code"] == "placeholders_changed"))
  end
end
