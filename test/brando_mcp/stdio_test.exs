defmodule BrandoMCP.StdioTest do
  use ExUnit.Case, async: false

  alias BrandoMCP.Stdio
  alias Mix.Tasks.Brando.Mcp, as: Task

  setup do
    BrandoMCP.Test.Env.setup()
  end

  describe "ensure_dev/2" do
    test "allows development and test" do
      assert Stdio.ensure_dev(:dev, false) == :ok
      assert Stdio.ensure_dev(:test, false) == :ok
    end

    test "refuses MIX_ENV=prod" do
      assert {:error, message} = Stdio.ensure_dev(:prod, false)
      assert message =~ "MIX_ENV=prod"
    end

    test "refuses inside a release, whatever the environment" do
      for env <- [:dev, :prod, nil] do
        assert {:error, message} = Stdio.ensure_dev(env, true)
        assert message =~ "release"
      end
    end
  end

  describe "resolve_user/1" do
    test "resolves an active user by email" do
      assert {:ok, %{id: 7}} = Stdio.resolve_user("dev@example.com")
      assert {:ok, %{id: 7}} = Stdio.resolve_user("  dev@example.com\n")
    end

    test "refuses without a user" do
      for missing <- [nil, "", "  "] do
        assert {:error, message} = Stdio.resolve_user(missing)
        assert message =~ "config :brando_mcp, user:"
        assert message =~ "--user"
      end
    end

    test "refuses :system and other non-email identities" do
      for other <- [:system, %{id: 1}, 1] do
        assert {:error, message} = Stdio.resolve_user(other)
        assert message =~ "must be a Brando user's email"
      end
    end

    test "refuses unknown, inactive and deleted users" do
      assert {:error, "There is no Brando user" <> _} = Stdio.resolve_user("nobody@example.com")

      assert {:error, "The Brando user inactive@example.com is not active."} =
               Stdio.resolve_user("inactive@example.com")

      assert {:error, _} = Stdio.resolve_user("gone@example.com")
    end
  end

  describe "start/1" do
    test "refuses when the host's Brando has no content tools" do
      Application.put_env(:brando_mcp, :content_tools, Brando.Missing.Tools)

      assert {:error, "This Brando version has no content proposal tools" <> _} =
               Stdio.start("dev@example.com")
    end
  end

  describe "mix brando.mcp" do
    test "refuses MIX_ENV=prod before booting the application" do
      env = Mix.env()
      Mix.env(:prod)

      try do
        assert_raise Mix.Error, ~r/MIX_ENV=prod/, fn ->
          Task.run(["--user", "dev@example.com"])
        end
      after
        Mix.env(env)
      end
    end

    test "refuses inside a release" do
      System.put_env("RELEASE_NAME", "my_app")

      try do
        assert_raise Mix.Error, ~r/release/, fn -> Task.run(["--user", "dev@example.com"]) end
      after
        System.delete_env("RELEASE_NAME")
      end
    end

    test "refuses the removed HTTP transport" do
      assert_raise Mix.Error, ~r/serves stdio only/, fn -> Task.run(["--transport", "http"]) end
    end

    test "refuses without a configured user" do
      assert_raise Mix.Error, ~r/needs a Brando user/, fn -> Task.run([]) end
    end

    test "refuses an unknown --user, over a configured one" do
      Application.put_env(:brando_mcp, :user, "dev@example.com")

      assert_raise Mix.Error, ~r/no Brando user with the email nobody@example.com/, fn ->
        Task.run(["--user", "nobody@example.com"])
      end
    end
  end
end
