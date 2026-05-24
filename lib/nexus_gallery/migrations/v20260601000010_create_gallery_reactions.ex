defmodule NexusGallery.Migrations.V20260601000010CreateGalleryReactions do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_reactions, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :uuid, null: false
      add :subject_type, :string, null: false
      add :subject_id,   :uuid, null: false
      add :emoji,        :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nexus_gallery_reactions, [:user_id, :subject_type, :subject_id, :emoji])
    create index(:nexus_gallery_reactions, [:subject_type, :subject_id])
  end
end
