defmodule NexusGallery.Harvest do
  @moduledoc """
  Handles harvesting images from forum posts into the gallery.

  When a post is created or updated, this module:
  1. Fetches the post body and its forum tag slugs from the DB.
  2. Checks which forum tag slugs have harvest mappings to gallery tags.
  3. Extracts /uploads/posts/ image URLs from the post body.
  4. For each image URL not already harvested from this post, creates a
     published gallery item owned by the post's original author.
  5. Tags the new item with the mapped gallery tag.
  """

  import Ecto.Query

  alias Nexus.Repo
  alias NexusGallery.Items

  @doc """
  Called from handle_event. Processes a post for harvestable images.
  post_id is an integer. settings is the extension settings map.
  """
  def process_post(post_id, settings) do
    unless parse_bool(settings["harvest_enabled"]) do
      :ok
    else
      case fetch_post(post_id) do
        nil  -> :ok
        post -> do_harvest(post, settings)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_harvest(post, _settings) do
    # Get forum tag slugs on this post
    forum_slugs = fetch_forum_tag_slugs(post.id)
    if forum_slugs == [] do
      :ok
    else
      # Find harvest mappings for these slugs
      mappings = fetch_mappings_for_slugs(forum_slugs)
      if mappings == [] do
        :ok
      else
        # Extract image URLs from post body
        image_urls = extract_image_urls(post.body)
        if image_urls == [] do
          :ok
        else
          # Resolve gallery_tag_ids from mappings (all matching slugs)
          gallery_tag_ids =
            mappings
            |> Enum.map(& &1.gallery_tag_id_str)
            |> Enum.uniq()

          # For each image URL, create a gallery item if not already harvested
          Enum.each(image_urls, fn url ->
            unless Items.harvested?(post.id, url) do
              case Items.harvest_item(%{
                user_id:        post.user_id,
                media_type:     "image",
                title:          post.title,
                file_url:       url,
                original_url:   url,
                is_draft:       false,
                source_post_id: post.id
              }) do
                {:ok, item} ->
                  Items.set_tags(item.id, gallery_tag_ids)
                {:error, reason} ->
                  require Logger
                  Logger.warning("[nexus-gallery] harvest_item failed for post #{post.id}: #{inspect(reason)}")
              end
            end
          end)
          :ok
        end
      end
    end
  end

  defp fetch_post(post_id) do
    Repo.one(
      from p in "posts",
        where: p.id == ^post_id and p.hidden == false,
        select: %{id: p.id, user_id: p.user_id, title: p.title, body: p.body}
    )
  end

  defp fetch_forum_tag_slugs(post_id) do
    Repo.all(
      from pt in "post_tags",
        join: t in "tags", on: t.id == pt.tag_id,
        where: pt.post_id == ^post_id,
        select: fragment("?::text", t.slug)
    )
  end

  defp fetch_mappings_for_slugs(forum_slugs) do
    Repo.all(
      from m in "nexus_gallery_harvest_mappings",
        where: m.forum_tag_slug in ^forum_slugs,
        select: %{
          id:                fragment("?::text", m.id),
          forum_tag_slug:    m.forum_tag_slug,
          gallery_tag_id_str: fragment("?::text", m.gallery_tag_id)
        }
    )
  end

  @doc "Extracts /uploads/posts/ image URLs from markdown or rich text body."
  def extract_image_urls(nil), do: []
  def extract_image_urls(body) do
    # Match markdown image syntax: ![alt](/uploads/posts/...)
    # and plain URLs in angle brackets or bare: /uploads/posts/...
    # and HTML img src="/uploads/posts/..."
    pattern = ~r{/uploads/posts/[^\s"')>\]]+}
    Regex.scan(pattern, body)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp parse_bool(true),    do: true
  defp parse_bool("true"),  do: true
  defp parse_bool(_),       do: false
end
