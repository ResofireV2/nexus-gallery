defmodule NexusGallery.Migrations.V20260601000010CreateGalleryReactions do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:nexus_gallery_reactions, primary_key: false) do
      add :id,           :uuid, primary_key: true, null: false
      add :user_id,      :integer, null: false
      add :subject_type, :string, null: false
      add :subject_id,   :uuid, null: false
      add :emoji,        :string, null: false
      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:nexus_gallery_reactions, [:user_id, :subject_type, :subject_id, :emoji])
    create_if_not_exists index(:nexus_gallery_reactions, [:subject_type, :subject_id])
  end
end
