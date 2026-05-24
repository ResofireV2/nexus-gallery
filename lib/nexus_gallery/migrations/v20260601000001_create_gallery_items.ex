defmodule NexusGallery.Migrations.V20260601000001CreateGalleryItems do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_items, primary_key: false) do
      add :id,          :uuid, primary_key: true, null: false
      add :user_id,     :uuid, null: false
      add :title,       :string
      add :description, :text
      add :media_type,  :string, null: false, default: "image"
      add :is_draft,    :boolean, null: false, default: true
      add :is_featured, :boolean, null: false, default: false
      add :view_count,  :integer, null: false, default: 0
      add :embed_url,   :string
      add :file_url,    :string
      add :original_url, :string
      add :thumbnail_url, :string
      add :width,       :integer
      add :height,      :integer
      add :upload_id,   :uuid
      add :source_post_id, :uuid
      timestamps(type: :utc_datetime)
    end

    create index(:nexus_gallery_items, [:user_id])
    create index(:nexus_gallery_items, [:media_type])
    create index(:nexus_gallery_items, [:is_draft])
    create index(:nexus_gallery_items, [:is_featured])
    create index(:nexus_gallery_items, [:inserted_at])
  end
end
