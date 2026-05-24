defmodule NexusGallery.Migrations.V20260601000005CreateGalleryCollectionItems do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_collection_items, primary_key: false) do
      add :collection_id, :uuid, null: false
      add :item_id,       :uuid, null: false
      add :position,      :integer, null: false, default: 0
    end

    create unique_index(:nexus_gallery_collection_items, [:collection_id, :item_id])
    create index(:nexus_gallery_collection_items, [:item_id])
  end
end
