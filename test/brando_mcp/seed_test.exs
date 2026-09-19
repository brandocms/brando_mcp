defmodule BrandoMCP.SeedTest do
  use ExUnit.Case, async: true

  alias BrandoMCP.Seed

  test "resolves batch-local references in dependency order" do
    entries = [
      %{
        "ref" => "manager",
        "attributes" => %{"title" => "Ada"}
      },
      %{
        "ref" => "employee",
        "attributes" => %{"title" => "Grace", "manager_id" => %{"$ref" => "manager"}}
      }
    ]

    assert {:ok, normalized} = Seed.normalize_entries(entries, %{"status" => "draft"}, 10)

    create = fn attributes, entry ->
      id = if entry.ref == "manager", do: 101, else: 102
      {:ok, Map.put(attributes, "id", id)}
    end

    assert {:ok, created} = Seed.apply_entries(Enum.reverse(normalized), create)

    employee =
      Enum.find(created, fn created_entry -> created_entry["ref"] == "employee" end)

    assert employee["entry"]["manager_id"] == 101
    assert employee["entry"]["status"] == "draft"
  end

  test "rejects unknown, duplicate, and cyclic references" do
    assert {:error, {:unknown_seed_refs, ["missing"]}} =
             Seed.normalize_entries(
               [%{"attributes" => %{"manager_id" => %{"$ref" => "missing"}}}],
               %{},
               10
             )

    assert {:error, {:duplicate_seed_refs, ["same"]}} =
             Seed.normalize_entries(
               [%{"ref" => "same", "attributes" => %{}}, %{"ref" => "same", "attributes" => %{}}],
               %{},
               10
             )

    assert {:error, :cyclic_seed_refs} =
             Seed.normalize_entries(
               [
                 %{"ref" => "one", "attributes" => %{"next_id" => %{"$ref" => "two"}}},
                 %{"ref" => "two", "attributes" => %{"next_id" => %{"$ref" => "one"}}}
               ],
               %{},
               10
             )
  end
end
