defmodule BrandoMCP.JSON do
  @moduledoc false

  alias BrandoMCP.Config

  @sensitive_fragments ~w(password passwd secret token api_key private_key access_key)

  def normalize(value, opts \\ []) do
    depth = Keyword.get(opts, :depth, Config.serializer_depth())
    do_normalize(value, depth)
  end

  def encode!(value) do
    value
    |> normalize()
    |> Jason.encode!(pretty: true)
  end

  defp do_normalize(nil, _depth), do: nil
  defp do_normalize(value, _depth) when is_boolean(value) or is_number(value), do: value

  defp do_normalize(value, _depth) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      %{"encoding" => "base64", "data" => Base.encode64(value)}
    end
  end

  defp do_normalize(value, _depth) when is_atom(value), do: Atom.to_string(value)
  defp do_normalize(%Date{} = value, _depth), do: Date.to_iso8601(value)
  defp do_normalize(%Time{} = value, _depth), do: Time.to_iso8601(value)
  defp do_normalize(%NaiveDateTime{} = value, _depth), do: NaiveDateTime.to_iso8601(value)
  defp do_normalize(%DateTime{} = value, _depth), do: DateTime.to_iso8601(value)

  defp do_normalize(%MapSet{} = value, depth),
    do: value |> MapSet.to_list() |> do_normalize(depth)

  defp do_normalize(%Regex{} = value, _depth), do: Regex.source(value)
  defp do_normalize(%URI{} = value, _depth), do: URI.to_string(value)

  defp do_normalize(%{__struct__: module}, _depth)
       when module == Ecto.Association.NotLoaded do
    %{"_state" => "not_loaded"}
  end

  defp do_normalize(%{__struct__: module} = value, depth) do
    if depth <= 0 do
      struct_reference(value, module)
    else
      value
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__spark_metadata__])
      |> Map.put("_type", inspect(module))
      |> do_normalize(depth - 1)
    end
  end

  defp do_normalize(value, depth) when is_map(value) do
    if depth < 0 do
      %{"_state" => "max_depth"}
    else
      Map.new(value, fn {key, item} ->
        normalized_key = normalize_key(key)

        normalized_value =
          if sensitive_key?(normalized_key) do
            "[REDACTED]"
          else
            do_normalize(item, depth - 1)
          end

        {normalized_key, normalized_value}
      end)
    end
  end

  defp do_normalize(value, depth) when is_list(value) do
    if depth < 0 do
      []
    else
      Enum.map(value, &do_normalize(&1, depth - 1))
    end
  end

  defp do_normalize(value, depth) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> do_normalize(depth)
  end

  defp do_normalize(value, _depth) when is_function(value), do: inspect(value)
  defp do_normalize(value, _depth) when is_pid(value), do: inspect(value)
  defp do_normalize(value, _depth) when is_port(value), do: inspect(value)
  defp do_normalize(value, _depth) when is_reference(value), do: inspect(value)
  defp do_normalize(value, _depth), do: inspect(value)

  defp struct_reference(value, module) do
    %{"_type" => inspect(module)}
    |> maybe_put_id(Map.get(value, :id))
  end

  defp maybe_put_id(map, nil), do: map
  defp maybe_put_id(map, id), do: Map.put(map, "id", do_normalize(id, 0))

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: inspect(key)

  defp sensitive_key?(key) do
    normalized = String.downcase(key)
    Enum.any?(@sensitive_fragments, &String.contains?(normalized, &1))
  end
end
