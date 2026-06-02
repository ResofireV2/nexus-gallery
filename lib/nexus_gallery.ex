defmodule NexusGallery do
  use Nexus.Extensions.Behaviour

  @slug "nexus-gallery"

  # ---------------------------------------------------------------------------
  # Migrations
  # ---------------------------------------------------------------------------

  @impl true
  def migrations do
    [
      NexusGallery.Migrations.V1CreateGalleryItems,
      NexusGallery.Migrations.V2CreateGalleryTags,
      NexusGallery.Migrations.V3CreateGalleryItemTags,
      NexusGallery.Migrations.V4CreateGalleryCollections,
      NexusGallery.Migrations.V5CreateGalleryCollectionItems,
      NexusGallery.Migrations.V6CreateGalleryCollectionTags,
      NexusGallery.Migrations.V7CreateGalleryRatings,
      NexusGallery.Migrations.V8CreateGalleryComments,
      NexusGallery.Migrations.V9CreateGallerySubscriptions,
      NexusGallery.Migrations.V10CreateGalleryReactions,
      NexusGallery.Migrations.V11CreateGalleryHarvestMappings,
      NexusGallery.Migrations.V12FixUserIdTypes,
      NexusGallery.Migrations.V13AddSourceReplyId,
      NexusGallery.Migrations.V14AddPendingApprovalToItems,
    ]
  end

  # ---------------------------------------------------------------------------
  # Routes — Elixir API plug router
  # ---------------------------------------------------------------------------

  @impl true
  def routes do
    [{"/", NexusGallery.ApiRouter, []}]
  end

  # ---------------------------------------------------------------------------
  # Hook handlers
  # Manifest declares post_created and post_updated for harvest (Phase 10).
  # Handlers are stubs in Phase 1 — harvest logic is added later.
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("post_created", %{post_id: post_id}, settings) do
    NexusGallery.Harvest.process_post(post_id, settings)
    :ok
  end
  def handle_event("post_updated", %{post_id: post_id}, settings) do
    NexusGallery.Harvest.process_post(post_id, settings)
    :ok
  end
  def handle_event("reply_created", %{reply_id: reply_id, post_id: post_id}, settings) do
    NexusGallery.Harvest.process_reply(reply_id, post_id, settings)
    :ok
  end
  def handle_event(_event, _payload, _settings), do: :ok

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def on_install(_settings), do: :ok

  @impl true
  def on_update(_from_version, _to_version), do: :ok

  @impl true
  def on_uninstall, do: :ok
end
