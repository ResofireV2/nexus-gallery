defmodule NexusGallery.Items do
  import Ecto.Query
  alias Nexus.Repo
  alias NexusGallery.Item

  @doc """
  Creates a draft item for a user. Returns {:ok, item} or {:error, changeset}.
  Called before the file is uploaded so we have a record_id to pass to Nexus.
  """
  def create_draft(user_id, media_type \\ "image") do
    %Item{}
    |> Item.draft_changeset(%{user_id: user_id, media_type: media_type})
    |> Repo.insert()
  end

  @doc "Returns a single item by id, or nil."
  def get_item(id) do
    Repo.get(Item, id)
  end

  @doc "Returns item with preloaded tags."
  def get_item_with_tags(id) do
    item = Repo.get(Item, id)
    if item, do: preload_tags(item), else: nil
  end

  @doc """
  Saves upload result fields (url, original_url, width, height, upload_id)
  onto an existing draft item.
  """
  def save_upload_result(%Item{} = item, attrs) do
    item
    |> Item.upload_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates metadata and optionally publishes a draft item.
  tag_ids is an optional list of tag UUID strings.
  Returns {:ok, item} or {:error, changeset}.
  """
  def update_and_publish(%Item{} = item, attrs, tag_ids \\ nil) do
    Repo.transaction(fn ->
      case item |> Item.publish_changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          if is_list(tag_ids), do: set_tags(updated.id, tag_ids)
          preload_tags(updated)

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
  # Tag associations
  # ---------------------------------------------------------------------------

  defp set_tags(item_id, tag_ids) do
    # Remove existing
    Repo.delete_all(from it in "nexus_gallery_item_tags", where: it.item_id == ^item_id)
    # Insert new
    rows = Enum.map(tag_ids, fn tag_id -> %{item_id: item_id, tag_id: tag_id} end)
    if rows != [] do
      Repo.insert_all("nexus_gallery_item_tags", rows, on_conflict: :nothing)
    end
  end

  defp preload_tags(%Item{} = item) do
    tag_ids =
      from(it in "nexus_gallery_item_tags",
        where: it.item_id == ^item.id,
        select: it.tag_id)
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
end
