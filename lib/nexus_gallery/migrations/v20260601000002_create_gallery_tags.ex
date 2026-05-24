defmodule NexusGallery.Migrations.V20260601000002CreateGalleryTags do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_tags, primary_key: false) do
      add :id,            :uuid, primary_key: true, null: false
      add :name,          :string, null: false
      add :slug,          :string, null: false
      add :color,         :string, null: false, default: "#7c5cfc"
      add :position,      :integer, null: false, default: 0
      add :allow_images,  :boolean, null: false, default: true
      add :allow_videos,  :boolean, null: false, default: true
      add :allow_embeds,  :boolean, null: false, default: true
      add :item_count,    :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nexus_gallery_tags, [:slug])
    create index(:nexus_gallery_tags, [:position])
  end
end
