defmodule NexusGallery.Migrations.V20260601000013AddSourceReplyId do
  use Ecto.Migration

  def change do
    execute """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_items'
            AND column_name = 'source_reply_id'
        ) THEN
          ALTER TABLE nexus_gallery_items ADD COLUMN source_reply_id integer;
        END IF;
      END $$;
    """, "SELECT 1"

    create_if_not_exists index(:nexus_gallery_items, [:source_reply_id])
  end
end
