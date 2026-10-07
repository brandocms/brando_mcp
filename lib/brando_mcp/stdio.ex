defmodule BrandoMCP.Stdio do
  @moduledoc """
  The development stdio server behind `mix brando.mcp`.

  It serves Brando's content-proposal tools to a local coding agent over
  standard input and output, as a named Brando user: every tool call carries
  that user's own permissions. It refuses to run in production or inside a
  release, and it has no network transport.
  """
  alias BrandoMCP.Config

  @no_user """
  BrandoMCP needs a Brando user to run as. Name one by email:

      # config/dev.exs
      config :brando_mcp, user: "dev@example.com"

  or pass `mix brando.mcp --user dev@example.com`. Every tool call then carries
  that user's own permissions. There is no default user.
  """

  @doc """
  `:ok` in development, or an error explaining why the server will not start:
  inside a release, or when `Mix.env()` is `:prod`.
  """
  def ensure_dev(env \\ mix_env(), release? \\ release?())

  def ensure_dev(_env, true) do
    {:error,
     "BrandoMCP's stdio server is a development tool and does not run inside a release. " <>
       "Use it with `mix brando.mcp` in a development checkout."}
  end

  def ensure_dev(:prod, _release?) do
    {:error,
     "BrandoMCP's stdio server is a development tool and does not run with MIX_ENV=prod. " <>
       "Run `mix brando.mcp` in development, against development data."}
  end

  def ensure_dev(_env, _release?), do: :ok

  @doc """
  Resolve `email` to an active Brando user. Without an email, or for anything
  other than an email, it refuses: BrandoMCP never acts as `:system` or a
  default user.
  """
  def resolve_user(email) when is_binary(email) do
    email = String.trim(email)
    users = Config.users()

    cond do
      email == "" ->
        {:error, @no_user}

      not Code.ensure_loaded?(users) ->
        {:error, "Brando is not loaded in this application, so there is no user to run as."}

      true ->
        case users.get_user(%{matches: %{email: email}}) do
          {:ok, %{active: true, deleted_at: nil} = user} -> {:ok, user}
          {:ok, _user} -> {:error, "The Brando user #{email} is not active."}
          _ -> {:error, "There is no Brando user with the email #{email}."}
        end
    end
  end

  def resolve_user(nil), do: {:error, @no_user}

  def resolve_user(other) do
    {:error,
     "config :brando_mcp, :user must be a Brando user's email, not #{inspect(other)}. " <>
       "BrandoMCP no longer runs as :system or a configured user struct."}
  end

  @doc """
  Start serving stdio as the user with `email`, after checking the
  environment and that the host's Brando has the content tools.
  Returns the server pid and the user.
  """
  def start(email, opts \\ []) do
    with :ok <- ensure_dev(),
         :ok <- ensure_tools(),
         {:ok, user} <- resolve_user(email),
         {:ok, pid} <- BrandoMCP.Server.start_link(Keyword.put(opts, :actor, user)) do
      {:ok, pid, user}
    end
  end

  defp ensure_tools do
    if BrandoMCP.Content.available?(),
      do: :ok,
      else:
        {:error,
         "This Brando version has no content proposal tools (Brando.Content.Proposals.Tools)."}
  end

  defp mix_env, do: if(Code.ensure_loaded?(Mix), do: Mix.env())

  # Releases ship without Mix and set RELEASE_ROOT and RELEASE_NAME.
  defp release? do
    not Code.ensure_loaded?(Mix) or
      Enum.any?(~w(RELEASE_ROOT RELEASE_NAME), &(System.get_env(&1) not in [nil, ""]))
  end
end
