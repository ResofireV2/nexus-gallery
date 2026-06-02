defmodule NexusGallery.Migrations.V13AddSourceReplyId do
  use Ecto.Migration

  def change do
    alter table(:nexus_gallery_items) do
      add_if_not_exists :source_reply_id, :integer, null: true
    end

    create_if_not_exists index(:nexus_gallery_items, [:source_reply_id])
  end
end
