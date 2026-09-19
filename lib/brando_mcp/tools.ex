defmodule BrandoMCP.Tools do
  @moduledoc false

  alias BrandoMCP.{Config, Result}

  def system_info(_args, state), do: invoke(:system_info, [], state)

  def list_blueprints(args, state), do: invoke(:list_blueprints, [args], state)

  def describe_blueprint(args, state) do
    invoke(:describe_blueprint, [value(args, :blueprint)], state)
  end

  def list_entries(args, state) do
    invoke(:list_entries, [value(args, :blueprint), args], state)
  end

  def get_entry(args, state) do
    invoke(:get_entry, [value(args, :blueprint), value(args, :id), args], state)
  end

  def create_entry(args, state) do
    invoke(
      :create_entry,
      [value(args, :blueprint), value(args, :attributes, %{}), args],
      state
    )
  end

  def update_entry(args, state) do
    invoke(
      :update_entry,
      [
        value(args, :blueprint),
        value(args, :id),
        value(args, :attributes, %{}),
        args
      ],
      state
    )
  end

  def delete_entry(args, state) do
    invoke(:delete_entry, [value(args, :blueprint), value(args, :id), args], state)
  end

  def seed_contract(args, state) do
    invoke(:seed_contract, [value(args, :blueprint), args], state)
  end

  def validate_seed_batch(args, state) do
    invoke(
      :validate_seed_batch,
      [value(args, :blueprint), value(args, :entries, []), args],
      state
    )
  end

  def apply_seed_batch(args, state) do
    invoke(
      :apply_seed_batch,
      [value(args, :blueprint), value(args, :entries, []), args],
      state
    )
  end

  def prepare_translation(args, state) do
    invoke(:prepare_translation, [value(args, :blueprint), value(args, :id), args], state)
  end

  def validate_translation(args, state) do
    invoke(
      :validate_translation,
      [
        value(args, :blueprint),
        value(args, :id),
        value(args, :translations, []),
        args
      ],
      state
    )
  end

  def apply_translation(args, state) do
    invoke(
      :apply_translation,
      [
        value(args, :blueprint),
        value(args, :id),
        value(args, :translations, []),
        args
      ],
      state
    )
  end

  def system_resource(_args, state), do: resource(:system_info, [], state)
  def blueprints_resource(_args, state), do: resource(:list_blueprints, [%{}], state)

  def blueprint_resource(args, state) do
    resource(:describe_blueprint, [value(args, :blueprint)], state)
  end

  def workflow_prompt(args, state) do
    blueprint = value(args, :blueprint, "the relevant blueprint")
    objective = value(args, :objective, "inspect and safely update content")

    prompt = """
    Work with Brando CMS to #{objective} for #{blueprint}.

    First inspect `brando_system_info`, list the blueprints, and describe the
    selected blueprint. Read the current entry before proposing a mutation.
    BrandoMCP writes may be disabled; if enabled, preserve fields that are not
    explicitly part of the requested change. Never call `brando_delete_entry`
    without direct user confirmation. For generated seed content, obtain the
    seed contract and validate the complete batch before asking to apply it.
    For translation, prepare the manifest, translate it with your connected
    LLM, validate it, and ask for confirmation before applying it.
    """

    {:ok,
     %{
       messages: [
         %{role: "user", content: %{type: "text", text: String.trim(prompt)}}
       ]
     }, state}
  end

  defp invoke(function, arguments, state) do
    adapter = Config.adapter()

    result =
      try do
        apply(adapter, function, arguments)
      rescue
        exception ->
          {:error, Exception.message(exception)}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end

    case result do
      {:ok, data} -> {:ok, Result.ok(data), state}
      {:error, reason} -> {:ok, Result.error(reason), state}
      other -> {:ok, Result.error({:unexpected_adapter_result, other}), state}
    end
  end

  defp resource(function, arguments, state) do
    adapter = Config.adapter()

    case apply(adapter, function, arguments) do
      {:ok, data} -> {:ok, Jason.encode!(BrandoMCP.JSON.normalize(data), pretty: true), state}
      {:error, reason} -> {:error, Result.normalize_error(reason), state}
    end
  rescue
    exception -> {:error, Exception.message(exception), state}
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
