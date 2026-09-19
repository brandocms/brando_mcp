defmodule BrandoMCP.Result do
  @moduledoc false

  alias BrandoMCP.JSON

  def ok(data) when is_map(data) do
    normalized = JSON.normalize(data)

    %{
      content: [%{type: "text", text: Jason.encode!(normalized, pretty: true)}],
      structuredContent: normalized
    }
  end

  def error(reason) do
    normalized = normalize_error(reason)
    text = normalized |> Map.fetch!("error") |> error_text()

    %{
      content: [%{type: "text", text: text}],
      structuredContent: normalized,
      isError: true
    }
  end

  def normalize_error(%{__struct__: module} = changeset) when module == Ecto.Changeset do
    %{
      "error" => "validation_failed",
      "valid" => Map.get(changeset, :valid?),
      "action" => JSON.normalize(Map.get(changeset, :action)),
      "errors" => normalize_changeset_errors(Map.get(changeset, :errors, []))
    }
  end

  def normalize_error({:error, reason}), do: normalize_error(reason)

  def normalize_error({kind, reason}) when is_atom(kind) do
    %{"error" => Atom.to_string(kind), "reason" => JSON.normalize(reason)}
  end

  def normalize_error(reason) when is_binary(reason), do: %{"error" => reason}
  def normalize_error(reason) when is_atom(reason), do: %{"error" => Atom.to_string(reason)}

  def normalize_error(reason),
    do: %{"error" => "operation_failed", "reason" => JSON.normalize(reason)}

  defp normalize_changeset_errors(errors) do
    Map.new(errors, fn {field, {message, metadata}} ->
      rendered =
        Enum.reduce(metadata, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)

      {to_string(field), rendered}
    end)
  end

  defp error_text(value) when is_binary(value), do: value
  defp error_text(value), do: inspect(value)
end
