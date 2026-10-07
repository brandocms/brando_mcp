defmodule BrandoMCP.Result do
  @moduledoc false

  # Brando's admin agent refuses a tool result over this size; MCP clients get
  # the same bound, so a result never costs a model more here than in the admin.
  @result_limit 24_000

  def ok(data) when is_map(data) do
    case Jason.encode(data) do
      {:ok, json} when byte_size(json) > @result_limit ->
        error("The result was too large (#{byte_size(json)} bytes). Narrow the request.")

      {:ok, json} ->
        %{content: [%{type: "text", text: json}], structuredContent: Jason.decode!(json)}

      {:error, exception} ->
        error("The result could not be encoded: #{Exception.message(exception)}")
    end
  end

  def error(message) do
    message = if is_binary(message), do: message, else: inspect(message)

    %{
      content: [%{type: "text", text: message}],
      structuredContent: %{"error" => message},
      isError: true
    }
  end
end
