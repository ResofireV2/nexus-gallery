defmodule NexusGallery.Migrations.V20260601000004CreateGalleryCollections do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_collections, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :integer, null: false
      add :title,        :string, null: false
      add :slug,         :string, null: false
      add :description,  :text
      add :cover_url,    :string
      add :is_draft,     :boolean, null: false, default: true
      add :is_featured,  :boolean, null: false, default: false
      add :item_count,   :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nexus_gallery_collections, [:slug])
    create index(:nexus_gallery_collections, [:user_id])
    create index(:nexus_gallery_collections, [:is_draft])
    create index(:nexus_gallery_collections, [:is_featured])
    create index(:nexus_gallery_collections, [:inserted_at])
  end
end
