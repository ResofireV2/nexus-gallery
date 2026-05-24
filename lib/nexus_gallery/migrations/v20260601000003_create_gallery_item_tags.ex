defmodule NexusGallery.Migrations.V20260601000003CreateGalleryItemTags do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_item_tags, primary_key: false) do
      add :item_id, :uuid, null: false
      add :tag_id,  :uuid, null: false
    end

    create unique_index(:nexus_gallery_item_tags, [:item_id, :tag_id])
    create index(:nexus_gallery_item_tags, [:tag_id])
  end
end
