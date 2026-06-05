defmodule NexusGallery.Migrations.V20260601000005CreateGalleryCollectionItems do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:nexus_gallery_collection_items, primary_key: false) do
      add :collection_id, :uuid, null: false
      add :item_id,       :uuid, null: false
      add :position,      :integer, null: false, default: 0
    end

    create_if_not_exists unique_index(:nexus_gallery_collection_items, [:collection_id, :item_id])
    create_if_not_exists index(:nexus_gallery_collection_items, [:item_id])
  end
end
