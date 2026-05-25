defmodule NexusGallery do
  use Nexus.Extensions.Behaviour

  @slug "nexus-gallery"

  # ---------------------------------------------------------------------------
  # Migrations
  # ---------------------------------------------------------------------------

  @impl true
  def migrations do
    [
      NexusGallery.Migrations.V20260601000001CreateGalleryItems,
      NexusGallery.Migrations.V20260601000002CreateGalleryTags,
      NexusGallery.Migrations.V20260601000003CreateGalleryItemTags,
      NexusGallery.Migrations.V20260601000004CreateGalleryCollections,
      NexusGallery.Migrations.V20260601000005CreateGalleryCollectionItems,
      NexusGallery.Migrations.V20260601000006CreateGalleryCollectionTags,
      NexusGallery.Migrations.V20260601000007CreateGalleryRatings,
      NexusGallery.Migrations.V20260601000008CreateGalleryComments,
      NexusGallery.Migrations.V20260601000009CreateGallerySubscriptions,
      NexusGallery.Migrations.V20260601000010CreateGalleryReactions,
      NexusGallery.Migrations.V20260601000011CreateGalleryHarvestMappings,
      NexusGallery.Migrations.V20260601000012FixUserIdTypes,
      NexusGallery.Migrations.V20260601000013AddSourceReplyId,
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
