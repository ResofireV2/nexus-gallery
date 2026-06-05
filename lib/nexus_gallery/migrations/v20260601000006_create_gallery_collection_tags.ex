defmodule NexusGallery.Migrations.V20260601000006CreateGalleryCollectionTags do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:nexus_gallery_collection_tags, primary_key: false) do
      add :collection_id, :uuid, null: false
      add :tag_id,        :uuid, null: false
    end

    create_if_not_exists unique_index(:nexus_gallery_collection_tags, [:collection_id, :tag_id])
    create_if_not_exists index(:nexus_gallery_collection_tags, [:tag_id])
  end
end
