defmodule NexusGallery.Migrations.V20260601000013AddSourceReplyId do
  use Ecto.Migration

  def change do
    alter table(:nexus_gallery_items) do
      add :source_reply_id, :integer, null: true
    end

    create index(:nexus_gallery_items, [:source_reply_id])
  end
end
