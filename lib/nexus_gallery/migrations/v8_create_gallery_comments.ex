defmodule NexusGallery.Migrations.V8CreateGalleryComments do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:nexus_gallery_comments, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :integer, null: false
      add :subject_type, :string, null: false
      add :subject_id,   :uuid, null: false
      add :body,         :text, null: false
      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:nexus_gallery_comments, [:subject_type, :subject_id])
    create_if_not_exists index(:nexus_gallery_comments, [:user_id])
    create_if_not_exists index(:nexus_gallery_comments, [:inserted_at])
  end
end
