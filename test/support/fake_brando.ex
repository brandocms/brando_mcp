defmodule BrandoMCP.Test.FakeBlueprint do
  defstruct [
    :id,
    :title,
    :body,
    :password_hint,
    :language,
    :status,
    :author_id,
    :cover_id
  ]

  def __blueprint__, do: true

  def __naming__ do
    %{
      application: "Demo",
      domain: "Content",
      schema: "Article",
      singular: "article",
      plural: "articles",
      table_name: "content_articles",
      id: "demo-content-article"
    }
  end

  def __modules__, do: %{context: BrandoMCP.Test.FakeContext}

  def __attributes__ do
    [
      %{name: :title, type: :text, opts: %{required: true}},
      %{name: :body, type: :text, opts: %{}},
      %{name: :language, type: :language, opts: %{values: [:en, :no]}},
      %{name: :status, type: :status, opts: %{values: [:draft, :published]}}
    ]
  end

  def __relations__, do: [%{name: :author, type: :belongs_to, opts: %{required: true}}]
  def __assets__, do: [%{name: :cover, type: :image, opts: %{}}]
  def __required_attrs__, do: [:title]
  def __required_relations__, do: [:author]
  def __required_assets__, do: []
  def __traits__, do: [{BrandoMCP.Test.FakeTrait, [enabled: true]}]
  def __forms__, do: [%{name: :default, default_params: %{"status" => "draft"}, fields: [:title]}]
  def __form__, do: hd(__forms__())
  def __factory__(attrs), do: Map.merge(%{status: :draft, language: :en}, attrs)
  def __blocks_fields__, do: []
  def __slug_fields__, do: []
  def has_alternates?, do: false

  def __listings__ do
    [
      %{
        name: :default,
        query: %{order: "asc title"},
        limit: 25,
        sortable: true,
        filters: [%{key: "title", label: "Title", type: :text, default: nil}],
        sorts: []
      }
    ]
  end

  def __schema__(:fields),
    do: [:id, :title, :body, :password_hint, :language, :status, :author_id, :cover_id]

  def __schema__(:associations), do: [:author]
  def __schema__(:embeds), do: []
  def __schema__(:primary_key), do: [:id]
  def __schema__(:type, :id), do: :id
  def __schema__(:type, :title), do: :string
  def __schema__(:type, :body), do: :string
  def __schema__(:type, :password_hint), do: :string
  def __schema__(:type, :language), do: :string
  def __schema__(:type, :status), do: :string
  def __schema__(:type, :author_id), do: :id
  def __schema__(:type, :cover_id), do: :id

  def changeset(struct, attrs, _user, _sequence, _opts) do
    title = Map.get(attrs, "title", Map.get(attrs, :title))
    errors = if title in [nil, ""], do: [title: {"can't be blank", []}], else: []

    %{
      valid?: errors == [],
      errors: errors,
      changes: attrs,
      data: struct
    }
  end
end

defmodule BrandoMCP.Test.FakeContext do
  def list_articles(opts) do
    notify({:list_articles, opts})

    {:ok,
     %{
       entries: [
         %{id: 1, title: "First", body: "Body", password_hint: "never return this"}
       ],
       pagination_meta: %{total_entries: 1, total_pages: 1}
     }}
  end

  def get_article(opts) do
    notify({:get_article, opts})

    id = get_in(opts, [:matches, :id])

    {:ok,
     %BrandoMCP.Test.FakeBlueprint{
       id: id,
       title: "First",
       body: "<p>Hello {{ name }}</p>",
       language: if(id == 99, do: :no, else: :en),
       status: :draft
     }}
  end

  def create_article(attrs, user, opts) do
    notify({:create_article, attrs, user, opts})
    {:ok, Map.merge(%{id: 2}, attrs)}
  end

  def update_article(id, attrs, user, opts) do
    notify({:update_article, id, attrs, user, opts})
    {:ok, attrs |> Map.put("id", id)}
  end

  def delete_article(id, user) do
    notify({:delete_article, id, user})
    {:ok, %{id: id, deleted_at: ~N[2026-07-30 12:00:00]}}
  end

  def duplicate_article(id, user, opts) do
    notify({:duplicate_article, id, user, opts})
    language = opts |> Keyword.fetch!(:change_fields) |> Keyword.fetch!(:language)

    {:ok,
     %BrandoMCP.Test.FakeBlueprint{
       id: 99,
       title: "First",
       body: "<p>Hello {{ name }}</p>",
       language: language,
       status: :draft
     }}
  end

  defp notify(message) do
    if pid = Application.get_env(:brando_mcp, :test_pid) do
      send(pid, message)
    end
  end
end

defmodule BrandoMCP.Test.FakeTrait do
end

defmodule BrandoMCP.Test.FakeTranslation do
  def collect_translatable_content(entry, _schema) do
    [
      {:field, :title, entry.title},
      {:field, :body, entry.body}
    ]
  end

  def apply_translations(items, entry, schema) do
    if pid = Application.get_env(:brando_mcp, :test_pid) do
      send(pid, {:apply_translations, items, entry, schema})
    end

    :ok
  end
end
