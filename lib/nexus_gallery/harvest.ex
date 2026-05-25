defmodule NexusGallery.Harvest do
  @moduledoc """
  Handles harvesting images from forum posts into the gallery.

  When a post is created or updated, this module:
  1. Fetches the post body and space from the DB.
  2. Checks if the post's space slug has a harvest mapping to a gallery tag.
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
    require Logger
    Logger.info("[nexus-gallery] harvest triggered for post_id=#{inspect(post_id)}")
    unless parse_bool(settings["harvest_enabled"]) do
      Logger.info("[nexus-gallery] harvest skipped — harvest_enabled is off (settings=#{inspect(settings)})")
      :ok
    else
      case fetch_post(post_id) do
        nil ->
          Logger.warning("[nexus-gallery] harvest — post #{inspect(post_id)} not found or hidden")
          :ok
        post ->
          Logger.info("[nexus-gallery] harvest — post found, space_id=#{inspect(post.space_id)}, body_length=#{String.length(post.body || "")}")
          do_harvest(post, settings)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_harvest(post, _settings) do
    require Logger
    # Get the post's space slug — harvest is space-based only
    space_slug = if post.space_id, do: fetch_space_slug(post.space_id), else: nil
    Logger.info("[nexus-gallery] harvest — space_slug=#{inspect(space_slug)}")
    if is_nil(space_slug) do
      Logger.warning("[nexus-gallery] harvest — no space slug found for space_id=#{inspect(post.space_id)}")
      :ok
    else
      # Find harvest mappings for this space slug
      mappings = fetch_mappings_for_slugs([space_slug])
      Logger.info("[nexus-gallery] harvest — mappings found=#{length(mappings)} for slug=#{inspect(space_slug)}")
      if mappings == [] do
        Logger.info("[nexus-gallery] harvest — no mapping for space slug #{inspect(space_slug)}, skipping")
        :ok
      else
        # Extract image URLs from post body
        image_urls = extract_image_urls(post.body)
        Logger.info("[nexus-gallery] harvest — image_urls found=#{inspect(image_urls)}")
        if image_urls == [] do
          Logger.info("[nexus-gallery] harvest — no image URLs in post body, skipping")
          :ok
        else
          # Resolve gallery_tag_ids from mappings (all matching slugs)
          gallery_tag_ids =
            mappings
            |> Enum.map(& &1.gallery_tag_id_str)
            |> Enum.uniq()

          # For each image URL, create a gallery item if not already harvested
          Enum.each(image_urls, fn url ->
            already = Items.harvested?(post.id, url)
            Logger.info("[nexus-gallery] harvest — url=#{inspect(url)} already_harvested=#{already}")
            unless already do
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
                  Logger.info("[nexus-gallery] harvest — created item #{inspect(item.id)}, tagging with #{inspect(gallery_tag_ids)}")
                  Items.set_tags(item.id, gallery_tag_ids)
                {:error, reason} ->
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
        select: %{id: p.id, user_id: p.user_id, title: p.title, body: p.body, space_id: p.space_id}
    )
  end

  defp fetch_space_slug(space_id) do
    Repo.one(
      from s in "spaces",
        where: s.id == ^space_id,
        select: fragment("?::text", s.slug)
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

  @doc """
  Extracts /uploads/posts/ image URLs from a post body.

  Nexus composer inserts images as [![alt](webpUrl)](originalUrl).
  We extract only the inner img src (the webp) to avoid creating duplicate
  gallery items for the same image (one per webp, one per original).
  """
  def extract_image_urls(nil), do: []
  def extract_image_urls(body) do
    # Extract inner img src from markdown image syntax: ![alt](url) or [![alt](url)](href)
    # Captures the URL inside the image brackets specifically.
    img_pattern = ~r{!\[[^\]]*\]\((/uploads/posts/[^\)\s]+)\)}
    Regex.scan(img_pattern, body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp parse_bool(true),    do: true
  defp parse_bool("true"),  do: true
  defp parse_bool(_),       do: false
end
