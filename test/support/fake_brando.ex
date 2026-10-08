defmodule BrandoMCP.Test.FakeTools do
  @moduledoc false
  # Stands in for Brando.Content.Proposals.Tools: the same registry shape
  # (definitions/0, call/3 with a Context struct). Every call is reported to
  # the process in `config :brando_mcp, :test_pid`, whichever process runs it.

  defmodule Context do
    @moduledoc false
    defstruct [:actor, :conversation_id, :proposal_id, :origin, :client, attachments: %{}]
  end

  @names ~w(list_content_types describe_content_type search_entries entry_outline list_modules
            describe_module request_media look_at_media list_entry_media list_selection_options
            list_attachments search_assets find_media_folders attach_folder prepare_proposal)

  def names, do: @names

  def definitions do
    for name <- @names do
      %{
        name: name,
        description: "Fake #{name}.",
        parameters: %{type: "object", properties: %{query: %{type: "string"}}}
      }
    end
  end

  def call(name, args, %Context{} = context) when name in @names do
    if pid = Application.get_env(:brando_mcp, :test_pid) do
      send(pid, {:called, name, args, context})

      if source = Process.get(:fake_activity_source),
        do: send(pid, {:called_as, name, source})
    end

    result(name, args, context)
  end

  def call(name, _args, _context), do: {:error, "Unknown tool #{inspect(name)}."}

  defp result("search_entries", args, context) do
    {:ok,
     %{
       entries: [%{content_type: "pages", id: 1, title: "Sommerro", query: args["query"]}],
       actor_id: context.actor.id
     }}
  end

  defp result("prepare_proposal", %{"operations" => []}, _context),
    do: {:error, "Operation 0: Unknown operation."}

  defp result("prepare_proposal", _args, context) do
    {:ok,
     %{
       proposal_id: "proposal-#{System.unique_integer([:positive])}",
       refines: context.proposal_id,
       note: "The user reviews and approves this in the admin. Nothing is saved yet."
     }}
  end

  defp result("entry_outline", _args, _context) do
    deep =
      Enum.reduce(1..8, %{text: "deepest"}, fn level, child ->
        %{level: level, children: [child]}
      end)

    {:ok, %{blocks: [deep]}}
  end

  defp result("list_entry_media", _args, _context),
    do: {:ok, %{media: List.duplicate(%{kind: :image, title: String.duplicate("x", 200)}, 200)}}

  defp result(_name, _args, _context), do: {:ok, %{ok: true}}
end

defmodule BrandoMCP.Test.FakeActivity do
  @moduledoc false
  # Stands in for Brando.Activity.with_source/3: reports the attribution to
  # the test process and marks the calls made inside it.

  def with_source(source, details, fun) when is_map(details) do
    if pid = Application.get_env(:brando_mcp, :test_pid),
      do: send(pid, {:with_source, source, details})

    previous = Process.put(:fake_activity_source, {source, details})

    try do
      fun.()
    after
      if previous,
        do: Process.put(:fake_activity_source, previous),
        else: Process.delete(:fake_activity_source)
    end
  end
end

defmodule BrandoMCP.Test.FakeUsers do
  @moduledoc false
  # Stands in for Brando.Users.get_user/1 with a `matches: %{email: …}` lookup.

  @users [
    %{id: 7, email: "dev@example.com", active: true, deleted_at: nil, role: :editor},
    %{id: 8, email: "inactive@example.com", active: false, deleted_at: nil, role: :editor},
    %{
      id: 9,
      email: "gone@example.com",
      active: true,
      deleted_at: ~U[2026-01-01 00:00:00Z],
      role: :editor
    }
  ]

  def get_user(%{matches: %{email: email}}) do
    case Enum.find(@users, &(&1.email == email)) do
      nil -> {:error, {:user, :not_found}}
      user -> {:ok, user}
    end
  end
end

defmodule BrandoMCP.Test.Env do
  @moduledoc false
  import ExUnit.Callbacks, only: [on_exit: 1]

  # Configure :brando_mcp for one test with the fakes, and restore the
  # application and logger environment afterwards (the stdio server lowers
  # the global log level).
  def setup(overrides \\ []) do
    original = Application.get_all_env(:brando_mcp)
    logger_level = Logger.level()
    primary = :logger.get_primary_config().level
    stdio_mode = Application.get_env(:ex_mcp, :stdio_mode)
    shell = Mix.shell()

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:brando_mcp),
          do: Application.delete_env(:brando_mcp, key)

      for {key, value} <- original, do: Application.put_env(:brando_mcp, key, value)
      Logger.configure(level: logger_level)
      Application.put_env(:logger, :level, logger_level)
      :logger.set_primary_config(:level, primary)
      Mix.shell(shell)

      if is_nil(stdio_mode),
        do: Application.delete_env(:ex_mcp, :stdio_mode),
        else: Application.put_env(:ex_mcp, :stdio_mode, stdio_mode)
    end)

    defaults = [
      content_tools: BrandoMCP.Test.FakeTools,
      users: BrandoMCP.Test.FakeUsers,
      activity: BrandoMCP.Test.FakeActivity,
      test_pid: self()
    ]

    for {key, value} <- Keyword.merge(defaults, overrides),
        do: Application.put_env(:brando_mcp, key, value)

    :ok
  end
end
