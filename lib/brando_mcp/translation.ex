defmodule BrandoMCP.Translation do
  @moduledoc false

  @html_pattern ~r/<\/?[A-Za-z][^>]*>/u
  @placeholder_pattern ~r/\{\{.*?\}\}|\{%.*?%\}|<%.*?%>/su

  def manifest(items, metadata) when is_list(items) and is_map(metadata) do
    units =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, index} -> unit(item, index) end)

    digest = digest(metadata, units)

    metadata
    |> Map.put("source_digest", digest)
    |> Map.put("items", units)
    |> Map.put("count", length(units))
  end

  def validate(manifest, source_digest, translations) when is_map(manifest) do
    errors =
      []
      |> validate_digest(manifest, source_digest)
      |> validate_translations(manifest["items"], translations)

    if errors == [] do
      by_key = translations_by_key(translations)
      ordered = Enum.map(manifest["items"], &Map.fetch!(by_key, &1["key"]))

      {:ok,
       %{
         "valid" => true,
         "source_digest" => manifest["source_digest"],
         "count" => length(ordered),
         "translations" => ordered
       }}
    else
      {:error,
       %{
         "valid" => false,
         "source_digest" => manifest["source_digest"],
         "errors" => Enum.reverse(errors)
       }}
    end
  end

  def compatible_shapes?(source_items, target_items) do
    Enum.map(source_items, &shape/1) == Enum.map(target_items, &shape/1)
  end

  def apply_text(item, translated_text) when is_tuple(item) and is_binary(translated_text) do
    item
    |> Tuple.to_list()
    |> List.replace_at(tuple_size(item) - 1, translated_text)
    |> List.to_tuple()
  end

  defp unit(item, index) do
    source = source_text(item)
    format = if Regex.match?(@html_pattern, source), do: "html", else: "plain_text"

    %{
      "key" => "#{String.pad_leading(to_string(index), 4, "0")}:#{descriptor(item)}",
      "kind" => item |> elem(0) |> to_string(),
      "format" => format,
      "source" => source,
      "instructions" => instructions(format)
    }
  end

  defp descriptor({:field, field, _text}), do: "field:#{field}"
  defp descriptor({:var, id, _text}), do: "var:#{id}"
  defp descriptor({:ref, id, _text}), do: "ref:#{id}:text"
  defp descriptor({:ref_picture, id, field, _text}), do: "ref:#{id}:picture:#{field}"
  defp descriptor({:ref_video, id, field, _text}), do: "ref:#{id}:video:#{field}"

  defp descriptor({:ref_gallery, id, index, field, _text}),
    do: "ref:#{id}:gallery:#{index}:#{field}"

  defp descriptor({:table_var, id, _text}), do: "table_var:#{id}"

  defp descriptor({:identifier_meta, block_id, identifier, field, _text}),
    do: "block:#{block_id}:identifier:#{identifier}:#{field}"

  defp descriptor(item), do: item |> elem(0) |> to_string()

  defp source_text(item), do: elem(item, tuple_size(item) - 1)

  defp instructions("html"),
    do:
      "Translate only human-readable text. Preserve every HTML tag, attribute, URL, and template placeholder exactly."

  defp instructions(_format),
    do:
      "Translate the complete value. Preserve names, URLs, and template placeholders unless context clearly requires otherwise."

  defp digest(metadata, units) do
    payload =
      {
        metadata["blueprint"],
        metadata["entry_id"],
        metadata["source_language"],
        metadata["target_language"],
        Enum.map(units, &{&1["key"], &1["format"], &1["source"]})
      }

    :crypto.hash(:sha256, :erlang.term_to_binary(payload))
    |> Base.encode16(case: :lower)
  end

  defp validate_digest(errors, manifest, source_digest) do
    if is_binary(source_digest) and source_digest == manifest["source_digest"] do
      errors
    else
      [
        %{
          "code" => "source_changed",
          "message" => "The source digest does not match. Prepare the translation again."
        }
        | errors
      ]
    end
  end

  defp validate_translations(errors, units, translations) when is_list(translations) do
    expected_keys = units |> Enum.map(& &1["key"]) |> MapSet.new()
    keyed = normalized_translation_pairs(translations)
    supplied_keys = keyed |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    duplicate_keys =
      keyed
      |> Enum.frequencies_by(&elem(&1, 0))
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    errors
    |> add_error(
      duplicate_keys != [],
      "duplicate_keys",
      "Translation keys must be unique.",
      duplicate_keys
    )
    |> add_error(
      expected_keys != supplied_keys,
      "key_mismatch",
      "Translations must contain exactly the keys returned by prepare_translation.",
      %{
        "missing" => MapSet.difference(expected_keys, supplied_keys) |> MapSet.to_list(),
        "unknown" => MapSet.difference(supplied_keys, expected_keys) |> MapSet.to_list()
      }
    )
    |> validate_unit_values(units, Map.new(keyed))
  end

  defp validate_translations(errors, _units, _translations) do
    [
      %{"code" => "invalid_translations", "message" => "translations must be an array"}
      | errors
    ]
  end

  defp validate_unit_values(errors, units, translations) do
    Enum.reduce(units, errors, fn unit, acc ->
      case Map.get(translations, unit["key"]) do
        text when is_binary(text) and text != "" ->
          acc
          |> validate_html(unit, text)
          |> validate_placeholders(unit, text)

        _other ->
          [
            %{
              "code" => "blank_translation",
              "key" => unit["key"],
              "message" => "Translation must be a non-empty string."
            }
            | acc
          ]
      end
    end)
  end

  defp validate_html(errors, %{"format" => "html"} = unit, translated) do
    source_tags = Regex.scan(@html_pattern, unit["source"]) |> List.flatten()
    translated_tags = Regex.scan(@html_pattern, translated) |> List.flatten()

    add_error(
      errors,
      source_tags != translated_tags,
      "html_changed",
      "HTML tags or attributes changed during translation.",
      %{"key" => unit["key"]}
    )
  end

  defp validate_html(errors, _unit, _translated), do: errors

  defp validate_placeholders(errors, unit, translated) do
    source = Regex.scan(@placeholder_pattern, unit["source"]) |> List.flatten() |> Enum.sort()
    target = Regex.scan(@placeholder_pattern, translated) |> List.flatten() |> Enum.sort()

    add_error(
      errors,
      source != target,
      "placeholders_changed",
      "Template placeholders changed during translation.",
      %{"key" => unit["key"]}
    )
  end

  defp add_error(errors, false, _code, _message, _details), do: errors

  defp add_error(errors, true, code, message, details) do
    [%{"code" => code, "message" => message, "details" => details} | errors]
  end

  defp normalized_translation_pairs(translations) do
    Enum.map(translations, fn translation ->
      if is_map(translation) do
        {
          Map.get(translation, "key", Map.get(translation, :key)),
          Map.get(
            translation,
            "translation",
            Map.get(
              translation,
              :translation,
              Map.get(translation, "text", Map.get(translation, :text))
            )
          )
        }
      else
        {nil, nil}
      end
    end)
  end

  defp translations_by_key(translations) do
    Map.new(normalized_translation_pairs(translations))
  end

  defp shape({:field, field, _text}), do: {:field, field}
  defp shape({:var, _id, _text}), do: :var
  defp shape({:ref, _id, _text}), do: :ref
  defp shape({:ref_picture, _id, field, _text}), do: {:ref_picture, field}
  defp shape({:ref_video, _id, field, _text}), do: {:ref_video, field}
  defp shape({:ref_gallery, _id, index, field, _text}), do: {:ref_gallery, index, field}
  defp shape({:table_var, _id, _text}), do: :table_var

  defp shape({:identifier_meta, _block_id, identifier, field, _text}),
    do: {:identifier_meta, identifier, field}

  defp shape(item), do: elem(item, 0)
end
