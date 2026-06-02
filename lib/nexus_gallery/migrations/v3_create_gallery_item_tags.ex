defmodule NexusGallery.Migrations.V3CreateGalleryItemTags do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:nexus_gallery_item_tags, primary_key: false) do
      add :item_id, :uuid, null: false
      add :tag_id,  :uuid, null: false
    end

    create_if_not_exists unique_index(:nexus_gallery_item_tags, [:item_id, :tag_id])
    create_if_not_exists index(:nexus_gallery_item_tags, [:tag_id])
  end
end
