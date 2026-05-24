defmodule NexusGallery.Migrations.V20260601000008CreateGalleryComments do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_comments, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :uuid, null: false
      add :subject_type, :string, null: false
      add :subject_id,   :uuid, null: false
      add :body,         :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:nexus_gallery_comments, [:subject_type, :subject_id])
    create index(:nexus_gallery_comments, [:user_id])
    create index(:nexus_gallery_comments, [:inserted_at])
  end
end
