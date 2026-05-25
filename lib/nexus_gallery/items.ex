defmodule NexusGallery.Items do
  import Ecto.Query
  alias Nexus.Repo
  alias NexusGallery.Item

  @doc """
  Returns a paginated list of published gallery items with user info.
  """
  def list_items(opts \\ []) do
    page     = Keyword.get(opts, :page, 1) |> max(1)
    per_page = Keyword.get(opts, :per_page, 36) |> min(60) |> max(1)
    sort     = Keyword.get(opts, :sort, "newest")
    tag_slug = Keyword.get(opts, :tag_slug)
    media    = Keyword.get(opts, :media_type)
    uid      = Keyword.get(opts, :user_id)
    search   = Keyword.get(opts, :search)
    offset   = (page - 1) * per_page

    base = from i in Item, where: i.is_draft == false
    base = if media, do: from(i in base, where: i.media_type == ^media), else: base
    base = if uid,   do: from(i in base, where: i.user_id == ^uid),      else: base
    base =
      if search && search != "" do
        from i in base, where: ilike(i.title, ^"%#{search}%")
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

    total = Repo.aggregate(base, :count, :id)
    items = sorted |> limit(^per_page) |> offset(^offset) |> Repo.all()
    {enrich_list(items), total}
  end

  @doc "Creates an empty draft item."
  def create_draft(user_id, media_type \\ "image") do
    %Item{}
    |> Item.draft_changeset(%{user_id: user_id, media_type: media_type})
    |> Repo.insert()
  end

  @doc "Returns a single item struct by id, or nil."
  def get_item(id) do
    Repo.one(from i in Item, where: i.id == type(^uuid_bin(id), :uuid))
  end

  @doc "Returns item as a plain map with tags and user, or nil."
  def get_item_with_tags(id) do
    case Repo.one(from i in Item, where: i.id == type(^uuid_bin(id), :uuid)) do
      nil  -> nil
      item ->
        m = to_map(item)
        m = Map.put(m, :tags, fetch_tags(item.id))
        Map.put(m, :user, fetch_user(item.user_id))
    end
  end

  @doc "Saves upload result fields onto a draft item."
  def save_upload_result(%Item{} = item, attrs) do
    item |> Item.upload_changeset(attrs) |> Repo.update()
  end

  @doc "Updates metadata and optionally publishes a draft item."
  def update_and_publish(%Item{} = item, attrs, tag_ids \\ nil) do
    Repo.transaction(fn ->
      case item |> Item.publish_changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          if is_list(tag_ids), do: set_tags(updated.id, tag_ids)
          m = to_map(updated)
          m = Map.put(m, :tags, fetch_tags(updated.id))
          Map.put(m, :user, fetch_user(updated.user_id))
        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  @doc "Deletes an item and its tag associations."
  def delete_item(%Item{} = item) do
    id_str = uuid_str(item.id)
    Repo.transaction(fn ->
      Repo.delete_all(
        from it in "nexus_gallery_item_tags",
          where: it.item_id == type(^uuid_bin(id_str), :uuid)
      )
      Repo.delete!(item)
    end)
    |> case do
      {:ok, _}         -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------

  def stats do
    week_ago = DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)
    %{
      total_images: Repo.aggregate(from(i in Item, where: i.media_type == "image" and i.is_draft == false), :count, :id),
      total_videos: Repo.aggregate(from(i in Item, where: i.media_type == "video" and i.is_draft == false), :count, :id),
      total_embeds: Repo.aggregate(from(i in Item, where: i.media_type == "embed" and i.is_draft == false), :count, :id),
      this_week:    Repo.aggregate(from(i in Item, where: i.is_draft == false and i.inserted_at >= ^week_ago), :count, :id),
    }
  end

  def top_rated(limit \\ 4) do
    from(i in Item,
      where: i.is_draft == false,
      order_by: [desc: i.view_count, desc: i.inserted_at],
      limit: ^limit)
    |> Repo.all()
    |> enrich_list()
  end

  def top_uploaders(limit \\ 4) do
    from(i in Item,
      where: i.is_draft == false,
      group_by: i.user_id,
      select: %{user_id: i.user_id, count: count(i.id)},
      order_by: [desc: count(i.id)],
      limit: ^limit)
    |> Repo.all()
    |> enrich_uploader_list()
  end

  # ---------------------------------------------------------------------------
  # Private — struct to plain map
  # ---------------------------------------------------------------------------

  # Convert binary UUID to string. Ecto stores :binary_id fields as 16-byte
  # raw binaries in memory. Jason cannot encode raw binaries and will raise
  # Protocol.UndefinedError. Ecto.UUID.load/1 converts to the standard
  # "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" string form.
  defp uuid_str(nil), do: nil
  defp uuid_str(bin) when is_binary(bin) and byte_size(bin) == 16 do
    case Ecto.UUID.load(bin) do
      {:ok, str} -> str
      :error     -> nil
    end
  end
  defp uuid_str(str) when is_binary(str), do: str

  # Convert a string UUID to a 16-byte binary for Postgrex.
  # Postgrex's uuid encoder (OID 2950) expects a raw 16-byte binary.
  # Use type(^uuid_bin(id), :uuid) in queries — NOT type(^id, :binary_id).
  defp uuid_bin(nil), do: nil
  defp uuid_bin(bin) when is_binary(bin) and byte_size(bin) == 16, do: bin
  defp uuid_bin(str) when is_binary(str) do
    case Ecto.UUID.dump(str) do
      {:ok, bin} -> bin
      :error     -> nil
    end
  end

  defp to_map(%Item{} = i) do
    %{
      id:             uuid_str(i.id),
      user_id:        i.user_id,
      title:          i.title,
      description:    i.description,
      media_type:     i.media_type,
      is_draft:       i.is_draft,
      is_featured:    i.is_featured,
      view_count:     i.view_count,
      embed_url:      i.embed_url,
      file_url:       i.file_url,
      original_url:   i.original_url,
      thumbnail_url:  i.thumbnail_url,
      width:          i.width,
      height:         i.height,
      upload_id:      uuid_str(i.upload_id),
      source_post_id: i.source_post_id,
      inserted_at:    i.inserted_at,
      updated_at:     i.updated_at,
    }
  end

  # Fetch tags for an item.
  defp fetch_tags(item_id) do
    # Normalize to string UUID regardless of whether we received a binary or string
    id_str = uuid_str(item_id)
    tag_ids =
      from(it in "nexus_gallery_item_tags",
        where: it.item_id == type(^uuid_bin(id_str), :uuid),
        select: type(it.tag_id, :binary_id))
      |> Repo.all()

    if tag_ids == [] do
      []
    else
      from(t in NexusGallery.Tag,
        where: t.id in ^tag_ids,
        order_by: t.position)
      |> Repo.all()
      |> Enum.map(&tag_to_map/1)
    end
  end

  # Fetch a single user. Uses fragment("?::text", ...) to cast citext username.
  defp fetch_user(nil), do: nil
  defp fetch_user(user_id) do
    Repo.one(
      from u in "users",
        where: u.id == ^user_id,
        select: %{
          id:         u.id,
          username:   fragment("?::text", u.username),
          avatar_url: u.avatar_url
        }
    )
  end

  defp enrich_list(items) when is_list(items) do
    user_ids =
      items
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    users =
      if user_ids == [] do
        %{}
      else
        from(u in "users",
          where: u.id in ^user_ids,
          select: %{
            id:         u.id,
            username:   fragment("?::text", u.username),
            avatar_url: u.avatar_url
          })
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
      end

    Enum.map(items, fn item ->
      m = to_map(item)
      Map.put(m, :user, Map.get(users, item.user_id))
    end)
  end

  defp enrich_uploader_list(rows) do
    user_ids =
      rows
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    users =
      if user_ids == [] do
        %{}
      else
        from(u in "users",
          where: u.id in ^user_ids,
          select: %{
            id:         u.id,
            username:   fragment("?::text", u.username),
            avatar_url: u.avatar_url
          })
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
      end

    Enum.map(rows, fn row ->
      Map.put(row, :user, Map.get(users, row.user_id))
    end)
  end

  defp tag_to_map(tag) do
    %{
      id:           uuid_str(tag.id),
      name:         tag.name,
      slug:         tag.slug,
      color:        tag.color,
      position:     tag.position,
      allow_images: tag.allow_images,
      allow_videos: tag.allow_videos,
      allow_embeds: tag.allow_embeds,
      item_count:   tag.item_count,
    }
  end

  defp set_tags(item_id, tag_ids) do
    id_str = uuid_str(item_id)
    Repo.delete_all(
      from it in "nexus_gallery_item_tags",
        where: it.item_id == type(^uuid_bin(id_str), :uuid)
    )
    rows = Enum.map(tag_ids, fn tag_id ->
      %{item_id: id_str, tag_id: tag_id}
    end)
    if rows != [], do: Repo.insert_all("nexus_gallery_item_tags", rows, on_conflict: :nothing)
  end
end
