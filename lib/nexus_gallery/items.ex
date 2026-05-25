defmodule NexusGallery.Items do
  import Ecto.Query
  alias Nexus.Repo
  alias NexusGallery.Item

  @doc """
  Returns a paginated list of published gallery items with user info.
  Options:
    page:       integer, 1-based (default 1)
    per_page:   integer (default 36)
    sort:       "newest" | "oldest" | "top_rated" | "most_commented" (default "newest")
    tag_slug:   filter by gallery tag slug
    media_type: "image" | "video" | "embed"
    user_id:    filter by uploader user_id (integer)
    search:     title search string
  Returns {items_with_user, total_count}
  """
  def list_items(opts \\ []) do
    page      = Keyword.get(opts, :page, 1) |> max(1)
    per_page  = Keyword.get(opts, :per_page, 36) |> min(60) |> max(1)
    sort      = Keyword.get(opts, :sort, "newest")
    tag_slug  = Keyword.get(opts, :tag_slug)
    media     = Keyword.get(opts, :media_type)
    uid       = Keyword.get(opts, :user_id)
    search    = Keyword.get(opts, :search)

    offset = (page - 1) * per_page

    base =
      from i in Item,
        where: i.is_draft == false

    base =
      if media, do: from(i in base, where: i.media_type == ^media), else: base

    base =
      if uid, do: from(i in base, where: i.user_id == ^uid), else: base

    base =
      if search && search != "" do
        pattern = "%#{search}%"
        from i in base, where: ilike(i.title, ^pattern)
      else
        base
      end

    base =
      if tag_slug do
        from i in base,
          join: it in "nexus_gallery_item_tags", on: it.item_id == i.id,
          join: t  in "nexus_gallery_tags",      on: t.id == it.tag_id,
          where: t.slug == ^tag_slug
      else
        base
      end

    sorted =
      case sort do
        "oldest"         -> from i in base, order_by: [asc:  i.inserted_at, asc:  i.id]
        "top_rated"      -> from i in base, order_by: [desc: i.view_count,  desc: i.inserted_at]
        "most_commented" -> from i in base, order_by: [desc: i.view_count,  desc: i.inserted_at]
        _                -> from i in base, order_by: [desc: i.inserted_at, desc: i.id]
      end

    total   = Repo.aggregate(base, :count, :id)
    items   = sorted |> limit(^per_page) |> offset(^offset) |> Repo.all()
    enriched = enrich_with_users(items)

    {enriched, total}
  end

  @doc "Creates an empty draft item. Returns {:ok, item} or {:error, changeset}."
  def create_draft(user_id, media_type \\ "image") do
    %Item{}
    |> Item.draft_changeset(%{user_id: user_id, media_type: media_type})
    |> Repo.insert()
  end

  @doc "Returns a single item by id, or nil."
  def get_item(id) do
    Repo.get(Item, id)
  end

  @doc "Returns item with preloaded tags and user info."
  def get_item_with_tags(id) do
    case Repo.get(Item, id) do
      nil  -> nil
      item ->
        item
        |> preload_tags()
        |> enrich_with_user()
    end
  end

  @doc "Saves upload result fields onto a draft item."
  def save_upload_result(%Item{} = item, attrs) do
    item
    |> Item.upload_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates metadata and optionally publishes a draft item.
  tag_ids is an optional list of tag UUID strings.
  """
  def update_and_publish(%Item{} = item, attrs, tag_ids \\ nil) do
    Repo.transaction(fn ->
      case item |> Item.publish_changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          if is_list(tag_ids), do: set_tags(updated.id, tag_ids)
          updated
          |> preload_tags()
          |> enrich_with_user()

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  @doc "Deletes an item and its tag associations."
  def delete_item(%Item{} = item) do
    Repo.transaction(fn ->
      Repo.delete_all(from it in "nexus_gallery_item_tags", where: it.item_id == ^item.id)
      Repo.delete!(item)
    end)
    |> case do
      {:ok, _}         -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Stats — used by admin Stats tab and right widgets
  # ---------------------------------------------------------------------------

  def stats do
    total_images  = Repo.aggregate(from(i in Item, where: i.media_type == "image"  and i.is_draft == false), :count, :id)
    total_videos  = Repo.aggregate(from(i in Item, where: i.media_type == "video"  and i.is_draft == false), :count, :id)
    total_embeds  = Repo.aggregate(from(i in Item, where: i.media_type == "embed"  and i.is_draft == false), :count, :id)
    week_ago      = DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)
    this_week     = Repo.aggregate(from(i in Item, where: i.is_draft == false and i.inserted_at >= ^week_ago), :count, :id)

    %{
      total_images:  total_images,
      total_videos:  total_videos,
      total_embeds:  total_embeds,
      this_week:     this_week
    }
  end

  def top_rated(limit \\ 4) do
    from(i in Item,
      where: i.is_draft == false,
      order_by: [desc: i.view_count, desc: i.inserted_at],
      limit: ^limit)
    |> Repo.all()
    |> enrich_with_users()
  end

  def top_uploaders(limit \\ 4) do
    from(i in Item,
      where: i.is_draft == false,
      group_by: i.user_id,
      select: %{user_id: i.user_id, count: count(i.id)},
      order_by: [desc: count(i.id)],
      limit: ^limit)
    |> Repo.all()
    |> enrich_uploader_users()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp set_tags(item_id, tag_ids) do
    Repo.delete_all(from it in "nexus_gallery_item_tags", where: it.item_id == ^item_id)
    rows = Enum.map(tag_ids, fn tag_id -> %{item_id: item_id, tag_id: tag_id} end)
    if rows != [] do
      Repo.insert_all("nexus_gallery_item_tags", rows, on_conflict: :nothing)
    end
  end

  defp preload_tags(%Item{} = item) do
    tag_ids =
      from(it in "nexus_gallery_item_tags", where: it.item_id == ^item.id, select: it.tag_id)
      |> Repo.all()

    tags =
      if tag_ids == [] do
        []
      else
        from(t in NexusGallery.Tag, where: t.id in ^tag_ids, order_by: t.position)
        |> Repo.all()
      end

    Map.put(item, :tags, tags)
  end

  # Fetch user rows for a list of items in one query using string table name.
  defp enrich_with_users(items) when is_list(items) do
    user_ids = items |> Enum.map(& &1.user_id) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    users =
      if user_ids == [] do
        %{}
      else
        from(u in "users",
          where: u.id in ^user_ids,
          select: {u.id, u.username, u.avatar_url})
        |> Repo.all()
        |> Map.new(fn {id, username, avatar} -> {id, %{id: id, username: username, avatar_url: avatar}} end)
      end

    Enum.map(items, fn item ->
      Map.put(item, :user, Map.get(users, item.user_id))
    end)
  end

  defp enrich_with_user(%Item{} = item) do
    user =
      if item.user_id do
        case Repo.one(from u in "users", where: u.id == ^item.user_id, select: {u.id, u.username, u.avatar_url}) do
          {id, username, avatar} -> %{id: id, username: username, avatar_url: avatar}
          nil                    -> nil
        end
      end

    Map.put(item, :user, user)
  end

  defp enrich_uploader_users(rows) do
    user_ids = Enum.map(rows, & &1.user_id)
    users =
      if user_ids == [] do
        %{}
      else
        from(u in "users",
          where: u.id in ^user_ids,
          select: {u.id, u.username, u.avatar_url})
        |> Repo.all()
        |> Map.new(fn {id, username, avatar} -> {id, %{id: id, username: username, avatar_url: avatar}} end)
      end

    Enum.map(rows, fn row ->
      Map.put(row, :user, Map.get(users, row.user_id))
    end)
  end
end
