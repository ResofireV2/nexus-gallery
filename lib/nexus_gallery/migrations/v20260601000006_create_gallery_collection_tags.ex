defmodule NexusGallery.Migrations.V20260601000006CreateGalleryCollectionTags do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_collection_tags, primary_key: false) do
      add :collection_id, :uuid, null: false
      add :tag_id,        :uuid, null: false
    end

    create unique_index(:nexus_gallery_collection_tags, [:collection_id, :tag_id])
    create index(:nexus_gallery_collection_tags, [:tag_id])
  end
end
