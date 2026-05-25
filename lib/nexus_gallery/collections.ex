defmodule NexusGallery.Collections do
  import Ecto.Query
  alias Nexus.Repo
  alias NexusGallery.{Collection, Item}

  # ---------------------------------------------------------------------------
  # List
  # ---------------------------------------------------------------------------

  def list_collections(opts \\ []) do
    page     = Keyword.get(opts, :page, 1) |> max(1)
    per_page = Keyword.get(opts, :per_page, 24) |> min(60) |> max(1)
    sort     = Keyword.get(opts, :sort, "newest")
    user_id  = Keyword.get(opts, :user_id)
    search   = Keyword.get(opts, :search)
    offset   = (page - 1) * per_page

    base = from c in Collection, where: c.is_draft == false

    base = if user_id, do: from(c in base, where: c.user_id == ^user_id), else: base
    base =
      if search && search != "" do
        from c in base, where: ilike(c.title, ^"%#{search}%")
      else
        base
      end

    sorted =
      case sort do
        "oldest" -> from c in base, order_by: [asc: c.inserted_at]
        _        -> from c in base, order_by: [desc: c.inserted_at]
      end

    total       = Repo.aggregate(base, :count, :id)
    collections = sorted |> limit(^per_page) |> offset(^offset) |> Repo.all()
    enriched    = enrich_with_users(collections)
    {enriched, total}
  end

  # ---------------------------------------------------------------------------
  # Single
  # ---------------------------------------------------------------------------

  def get_collection_by_slug(slug) do
    Repo.get_by(Collection, slug: slug)
  end

  def get_collection_with_items(slug) do
    case Repo.get_by(Collection, slug: slug) do
      nil  -> nil
      coll ->
        coll
        |> to_map()
        |> put_items()
        |> put_user()
        |> put_tags()
    end
  end

  # ---------------------------------------------------------------------------
  # Create / Update / Delete
  # ---------------------------------------------------------------------------

  def create_collection(user_id, attrs) do
    slug_base = Collection.slugify(attrs["title"] || "")
    slug      = unique_slug(slug_base)

    %Collection{}
    |> Collection.create_changeset(Map.merge(attrs, %{"user_id" => user_id, "slug" => slug}))
    |> Repo.insert()
  end

  def update_collection(%Collection{} = coll, attrs) do
    attrs =
      if Map.has_key?(attrs, "title") and not Map.has_key?(attrs, "slug") do
        Map.put(attrs, "slug", unique_slug(Collection.slugify(attrs["title"]), coll.slug))
      else
        attrs
      end

    coll
    |> Collection.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_collection(%Collection{} = coll) do
    Repo.transaction(fn ->
      {:ok, id_bin} = Ecto.UUID.dump(uuid_str(coll.id))
      Repo.delete_all(from ci in "nexus_gallery_collection_items", where: ci.collection_id == ^id_bin)
      Repo.delete_all(from ct in "nexus_gallery_collection_tags",  where: ct.collection_id == ^id_bin)
      Repo.delete!(coll)
    end)
    |> case do
      {:ok, _}         -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Items in collection
  # ---------------------------------------------------------------------------

  def add_item(%Collection{} = coll, item_id_str) do
    {:ok, coll_bin} = Ecto.UUID.dump(uuid_str(coll.id))
    {:ok, item_bin} = Ecto.UUID.dump(item_id_str)

    already_in = Repo.aggregate(
      from(ci in "nexus_gallery_collection_items",
        where: ci.collection_id == ^coll_bin and ci.item_id == ^item_bin),
      :count, :collection_id
    ) > 0

    if already_in do
      {:error, "Item is already in this collection"}
    else
      next_pos = Repo.aggregate(
        from(ci in "nexus_gallery_collection_items",
          where: ci.collection_id == ^coll_bin),
        :count, :collection_id
      )
      Repo.insert_all("nexus_gallery_collection_items", [%{
        collection_id: coll_bin,
        item_id:       item_bin,
        position:      next_pos
      }])
      Repo.update_all(
        from(c in Collection, where: c.id == type(^uuid_str(coll.id), :binary_id)),
        inc: [item_count: 1]
      )
      # Auto-set cover_url from first item's file_url if collection has no cover yet
      if is_nil(coll.cover_url) do
        item_file_url = Repo.one(
          from(i in NexusGallery.Item,
            where: i.id == type(^item_id_str, :binary_id),
            select: i.file_url)
        )
        if item_file_url do
          Repo.update_all(
            from(c in Collection,
              where: c.id == type(^uuid_str(coll.id), :binary_id) and is_nil(c.cover_url)),
            set: [cover_url: item_file_url]
          )
        end
      end
      :ok
    end
  end

  def remove_item(%Collection{} = coll, item_id_str) do
    {:ok, coll_bin} = Ecto.UUID.dump(uuid_str(coll.id))
    {:ok, item_bin} = Ecto.UUID.dump(item_id_str)

    {count, _} = Repo.delete_all(
      from ci in "nexus_gallery_collection_items",
        where: ci.collection_id == ^coll_bin and ci.item_id == ^item_bin
    )

    if count > 0 do
      Repo.update_all(
        from(c in Collection, where: c.id == type(^uuid_str(coll.id), :binary_id)),
        inc: [item_count: -1]
      )
      :ok
    else
      {:error, "Item not in collection"}
    end
  end

  # Returns list of collection maps that contain the given item
  def collections_for_item(item_id_str, user_id) do
    case Ecto.UUID.dump(item_id_str) do
      {:ok, item_bin} ->
        coll_ids =
          from(ci in "nexus_gallery_collection_items",
            where: ci.item_id == ^item_bin,
            select: fragment("?::text", ci.collection_id))
          |> Repo.all()

        if coll_ids == [] do
          []
        else
          from(c in Collection,
            where: fragment("?::text", c.id) in ^coll_ids and c.user_id == ^user_id)
          |> Repo.all()
          |> Enum.map(&to_map/1)
        end
      :error -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp to_map(%Collection{} = c) do
    %{
      id:          uuid_str(c.id),
      user_id:     c.user_id,
      title:       c.title,
      slug:        c.slug,
      description: c.description,
      cover_url:   c.cover_url,
      is_draft:    c.is_draft,
      is_featured: c.is_featured,
      item_count:  c.item_count,
      inserted_at: c.inserted_at,
      updated_at:  c.updated_at,
    }
  end

  defp put_user(coll_map) do
    user =
      case Repo.one(
        from u in "users",
          where: u.id == ^coll_map.user_id,
          select: %{id: u.id, username: fragment("?::text", u.username), avatar_url: u.avatar_url}
      ) do
        nil  -> nil
        u    -> u
      end
    Map.put(coll_map, :user, user)
  end

  defp put_items(coll_map) do
    {:ok, coll_bin} = Ecto.UUID.dump(coll_map.id)
    item_ids =
      from(ci in "nexus_gallery_collection_items",
        where: ci.collection_id == ^coll_bin,
        order_by: ci.position,
        select: type(ci.item_id, :binary_id))
      |> Repo.all()

    items =
      if item_ids == [] do
        []
      else
        from(i in Item,
          where: i.id in ^item_ids and i.is_draft == false)
        |> Repo.all()
        |> NexusGallery.Items.enrich_list_public()
      end

    Map.put(coll_map, :items, items)
  end

  defp put_tags(coll_map) do
    {:ok, coll_bin} = Ecto.UUID.dump(coll_map.id)
    tag_ids =
      from(ct in "nexus_gallery_collection_tags",
        where: ct.collection_id == ^coll_bin,
        select: type(ct.tag_id, :binary_id))
      |> Repo.all()

    tags =
      if tag_ids == [] do
        []
      else
        from(t in NexusGallery.Tag,
          where: t.id in ^tag_ids,
          order_by: t.position)
        |> Repo.all()
        |> Enum.map(fn t ->
          %{id: uuid_str(t.id), name: t.name, slug: t.slug, color: t.color}
        end)
      end

    Map.put(coll_map, :tags, tags)
  end

  defp enrich_with_users(collections) when is_list(collections) do
    user_ids =
      collections |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    users =
      if user_ids == [] do
        %{}
      else
        from(u in "users",
          where: u.id in ^user_ids,
          select: %{id: u.id, username: fragment("?::text", u.username), avatar_url: u.avatar_url})
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
      end

    Enum.map(collections, fn c ->
      m = to_map(c)
      Map.put(m, :user, Map.get(users, c.user_id))
    end)
  end

  defp unique_slug(base, current_slug \\ nil) do
    slug = if base == "", do: "collection", else: base
    candidate = slug
    taken = from(c in Collection, where: c.slug == ^candidate and c.slug != ^(current_slug || ""))
    if Repo.aggregate(taken, :count, :id) == 0 do
      candidate
    else
      unique_slug_loop(slug, 2, current_slug)
    end
  end

  defp unique_slug_loop(base, n, current_slug) do
    candidate = "#{base}-#{n}"
    taken = from(c in Collection, where: c.slug == ^candidate and c.slug != ^(current_slug || ""))
    if Repo.aggregate(taken, :count, :id) == 0 do
      candidate
    else
      unique_slug_loop(base, n + 1, current_slug)
    end
  end

  defp uuid_str(nil), do: nil
  defp uuid_str(bin) when is_binary(bin) and byte_size(bin) == 16 do
    case Ecto.UUID.load(bin) do
      {:ok, str} -> str
      :error     -> nil
    end
  end
  defp uuid_str(str) when is_binary(str), do: str
end
