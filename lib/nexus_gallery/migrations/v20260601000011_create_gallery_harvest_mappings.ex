defmodule NexusGallery.Migrations.V20260601000011CreateGalleryHarvestMappings do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_harvest_mappings, primary_key: false) do
      add :id,              :uuid, primary_key: true, null: false
      add :forum_tag_slug,  :string, null: false
      add :gallery_tag_id,  :uuid, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nexus_gallery_harvest_mappings, [:forum_tag_slug])
    create index(:nexus_gallery_harvest_mappings, [:gallery_tag_id])
  end
end
