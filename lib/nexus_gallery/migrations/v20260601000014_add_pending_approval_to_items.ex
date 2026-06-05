defmodule NexusGallery.Migrations.V20260601000014AddPendingApprovalToItems do
  use Ecto.Migration

  def change do
    execute """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_items'
            AND column_name = 'pending_approval'
        ) THEN
          ALTER TABLE nexus_gallery_items ADD COLUMN pending_approval boolean NOT NULL DEFAULT false;
        END IF;
      END $$;
    """, "SELECT 1"

    create_if_not_exists index(:nexus_gallery_items, [:pending_approval])
  end
end
