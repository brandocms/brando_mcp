defmodule BrandoMCP.Seed do
  @moduledoc false

  alias BrandoMCP.JSON

  @ecto_changeset Module.concat(["Ecto", "Changeset"])

  @type normalized_entry :: %{
          ref: String.t(),
          attributes: map(),
          dependencies: [String.t()],
          index: non_neg_integer()
        }

  def normalize_entries(entries, defaults, max_entries)
      when is_list(entries) and is_map(defaults) and is_integer(max_entries) do
    cond do
      entries == [] ->
        {:error, "entries must contain at least one seed entry"}

      length(entries) > max_entries ->
        {:error, "seed batch exceeds the configured maximum of #{max_entries} entries"}

      true ->
        entries
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
          case normalize_entry(entry, defaults, index) do
            {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, normalized} ->
            normalized
            |> Enum.reverse()
            |> validate_unique_refs()
            |> validate_dependency_graph()

          error ->
            error
        end
    end
  end

  def normalize_entries(_entries, _defaults, _max_entries),
    do: {:error, "entries must be an array"}

  def apply_entries(entries, create_fun) when is_list(entries) and is_function(create_fun, 2) do
    do_apply_entries(entries, %{}, [], create_fun)
  end

  def preview(changeset, entry, missing_required) do
    errors = changeset_errors(changeset)
    valid? = Map.get(changeset, :valid?, errors == %{})

    %{
      "ref" => entry.ref,
      "index" => entry.index,
      "valid" => valid?,
      "errors" => errors,
      "warnings" => required_warnings(missing_required),
      "attributes" => JSON.normalize(entry.attributes)
    }
  end

  def preview_attributes(value) do
    replace_refs(value, 1)
  end

  defp normalize_entry(entry, defaults, index) when is_map(entry) do
    attributes =
      case value(entry, :attributes) do
        nil -> Map.drop(entry, ["ref", :ref])
        attrs when is_map(attrs) -> attrs
        _other -> :invalid
      end

    if attributes == :invalid do
      {:error, "seed entry #{index + 1} attributes must be an object"}
    else
      ref =
        case value(entry, :ref) do
          nil -> "entry-#{index + 1}"
          ref when is_binary(ref) and ref != "" -> ref
          _other -> nil
        end

      if is_nil(ref) do
        {:error, "seed entry #{index + 1} ref must be a non-empty string"}
      else
        attributes = deep_merge(defaults, attributes)

        {:ok,
         %{
           ref: ref,
           attributes: attributes,
           dependencies: collect_refs(attributes),
           index: index
         }}
      end
    end
  end

  defp normalize_entry(_entry, _defaults, index),
    do: {:error, "seed entry #{index + 1} must be an object"}

  defp validate_unique_refs(entries) do
    duplicates =
      entries
      |> Enum.frequencies_by(& &1.ref)
      |> Enum.filter(fn {_ref, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates == [] do
      {:ok, entries}
    else
      {:error, {:duplicate_seed_refs, duplicates}}
    end
  end

  defp validate_dependency_graph({:error, _reason} = error), do: error

  defp validate_dependency_graph({:ok, entries}) do
    refs = MapSet.new(Enum.map(entries, & &1.ref))

    unknown =
      entries
      |> Enum.flat_map(& &1.dependencies)
      |> Enum.reject(&MapSet.member?(refs, &1))
      |> Enum.uniq()

    cond do
      unknown != [] ->
        {:error, {:unknown_seed_refs, unknown}}

      cyclic_dependencies?(entries) ->
        {:error, :cyclic_seed_refs}

      true ->
        {:ok, entries}
    end
  end

  defp cyclic_dependencies?(entries) do
    do_cyclic_dependencies?(entries, MapSet.new())
  end

  defp do_cyclic_dependencies?([], _resolved), do: false

  defp do_cyclic_dependencies?(pending, resolved) do
    {ready, blocked} =
      Enum.split_with(pending, fn entry ->
        Enum.all?(entry.dependencies, &MapSet.member?(resolved, &1))
      end)

    if ready == [] do
      true
    else
      next_resolved = Enum.reduce(ready, resolved, &MapSet.put(&2, &1.ref))
      do_cyclic_dependencies?(blocked, next_resolved)
    end
  end

  defp do_apply_entries([], _created_by_ref, created, _create_fun),
    do: {:ok, Enum.reverse(created)}

  defp do_apply_entries(pending, created_by_ref, created, create_fun) do
    {ready, blocked} =
      Enum.split_with(pending, fn entry ->
        Enum.all?(entry.dependencies, &Map.has_key?(created_by_ref, &1))
      end)

    if ready == [] do
      unresolved =
        Map.new(blocked, fn entry ->
          {entry.ref, Enum.reject(entry.dependencies, &Map.has_key?(created_by_ref, &1))}
        end)

      {:error, {:unresolved_or_cyclic_seed_refs, unresolved}}
    else
      Enum.reduce_while(ready, {:ok, created_by_ref, created}, fn entry, {:ok, refs, acc} ->
        with {:ok, attributes} <- resolve_refs(entry.attributes, refs),
             {:ok, result} <- create_fun.(attributes, entry) do
          id = entry_id(result)

          if is_nil(id) and referenced_later?(blocked, entry.ref) do
            {:halt, {:error, {:created_entry_has_no_id, entry.ref}}}
          else
            created_entry = %{"ref" => entry.ref, "entry" => result}
            {:cont, {:ok, Map.put(refs, entry.ref, id), [created_entry | acc]}}
          end
        else
          {:error, reason} -> {:halt, {:error, {:seed_entry_failed, entry.ref, reason}}}
        end
      end)
      |> case do
        {:ok, refs, acc} -> do_apply_entries(blocked, refs, acc, create_fun)
        error -> error
      end
    end
  end

  defp collect_refs(%{"$ref" => ref}) when is_binary(ref), do: [ref]
  defp collect_refs(%{:"$ref" => ref}) when is_binary(ref), do: [ref]

  defp collect_refs(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.flat_map(&collect_refs/1)
    |> Enum.uniq()
  end

  defp collect_refs(list) when is_list(list),
    do: Enum.flat_map(list, &collect_refs/1) |> Enum.uniq()

  defp collect_refs(_value), do: []

  defp resolve_refs(%{"$ref" => ref}, refs) when is_binary(ref), do: Map.fetch(refs, ref)
  defp resolve_refs(%{:"$ref" => ref}, refs) when is_binary(ref), do: Map.fetch(refs, ref)

  defp resolve_refs(map, refs) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_refs(value, refs) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        :error -> {:halt, {:error, {:unresolved_seed_ref, value}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_refs(list, refs) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case resolve_refs(value, refs) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        :error -> {:halt, {:error, {:unresolved_seed_ref, value}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp resolve_refs(value, _refs), do: {:ok, value}

  defp referenced_later?(entries, ref) do
    Enum.any?(entries, &(ref in &1.dependencies))
  end

  defp entry_id(%{"id" => id}), do: id
  defp entry_id(%{id: id}), do: id
  defp entry_id(_entry), do: nil

  defp changeset_errors(%{__struct__: module} = changeset) when module == @ecto_changeset do
    apply(@ecto_changeset, :traverse_errors, [changeset, &translate_error/1])
  end

  defp changeset_errors(changeset) do
    changeset
    |> Map.get(:errors, [])
    |> Enum.group_by(
      fn {field, _error} -> to_string(field) end,
      fn {_field, error} -> translate_error(error) end
    )
  end

  defp translate_error({message, opts}) when is_binary(message) and is_list(opts) do
    Enum.reduce(opts, message, fn {key, value}, translated ->
      String.replace(translated, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(message) when is_binary(message), do: message
  defp translate_error(error), do: inspect(error)

  defp required_warnings([]), do: []

  defp required_warnings(fields) do
    [
      %{
        "code" => "missing_required_fields",
        "fields" => Enum.map(fields, &to_string/1),
        "message" => "Draft changesets may allow these required fields to remain empty."
      }
    ]
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp replace_refs(%{"$ref" => ref}, replacement) when is_binary(ref), do: replacement
  defp replace_refs(%{:"$ref" => ref}, replacement) when is_binary(ref), do: replacement

  defp replace_refs(map, replacement) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, replace_refs(value, replacement)} end)
  end

  defp replace_refs(list, replacement) when is_list(list) do
    Enum.map(list, &replace_refs(&1, replacement))
  end

  defp replace_refs(value, _replacement), do: value

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
