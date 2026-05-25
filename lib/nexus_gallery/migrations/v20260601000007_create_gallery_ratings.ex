defmodule NexusGallery.Migrations.V20260601000007CreateGalleryRatings do
  use Ecto.Migration

  def change do
    create table(:nexus_gallery_ratings, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :integer, null: false
      add :subject_type, :string, null: false
      add :subject_id,   :uuid, null: false
      add :value,        :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nexus_gallery_ratings, [:user_id, :subject_type, :subject_id])
    create index(:nexus_gallery_ratings, [:subject_type, :subject_id])
  end
end
