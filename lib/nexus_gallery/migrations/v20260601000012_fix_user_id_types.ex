defmodule NexusGallery.Migrations.V20260601000012FixUserIdTypes do
  use Ecto.Migration

  # All six gallery tables had user_id created as :uuid in the Phase 1 migration
  # due to a bug. Nexus users.id is a bigserial integer. These tables are empty
  # so we drop and recreate the columns rather than attempting an in-place cast.
  # Idempotent: checks column type before modifying — safe to run on already-fixed DBs.

  def change do
    # Only run the fix if user_id is still uuid type
    execute """
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_items'
            AND column_name = 'user_id'
            AND data_type = 'uuid'
        ) THEN
          ALTER TABLE nexus_gallery_items DROP COLUMN user_id;
          ALTER TABLE nexus_gallery_items ADD COLUMN user_id integer NOT NULL DEFAULT 0;
          ALTER TABLE nexus_gallery_items ALTER COLUMN user_id DROP DEFAULT;
        END IF;
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_items'
            AND column_name = 'source_post_id'
            AND data_type = 'uuid'
        ) THEN
          ALTER TABLE nexus_gallery_items DROP COLUMN source_post_id;
          ALTER TABLE nexus_gallery_items ADD COLUMN source_post_id integer;
        END IF;
      END $$;
    """, "SELECT 1"

    execute """
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_collections'
            AND column_name = 'user_id'
            AND data_type = 'uuid'
        ) THEN
          ALTER TABLE nexus_gallery_collections DROP COLUMN user_id;
          ALTER TABLE nexus_gallery_collections ADD COLUMN user_id integer NOT NULL DEFAULT 0;
          ALTER TABLE nexus_gallery_collections ALTER COLUMN user_id DROP DEFAULT;
        END IF;
      END $$;
    """, "SELECT 1"

    execute """
      DO $$
      DECLARE
        tbl text;
      BEGIN
        FOREACH tbl IN ARRAY ARRAY['nexus_gallery_ratings','nexus_gallery_comments','nexus_gallery_subscriptions','nexus_gallery_reactions']
        LOOP
          IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = tbl
              AND column_name = 'user_id'
              AND data_type = 'uuid'
          ) THEN
            EXECUTE format('ALTER TABLE %I DROP COLUMN user_id', tbl);
            EXECUTE format('ALTER TABLE %I ADD COLUMN user_id integer NOT NULL DEFAULT 0', tbl);
            EXECUTE format('ALTER TABLE %I ALTER COLUMN user_id DROP DEFAULT', tbl);
          END IF;
        END LOOP;
      END $$;
    """, "SELECT 1"

    # Recreate indexes idempotently
    create_if_not_exists index(:nexus_gallery_items,         [:user_id])
    create_if_not_exists index(:nexus_gallery_collections,   [:user_id])
    create_if_not_exists unique_index(:nexus_gallery_ratings,       [:user_id, :subject_type, :subject_id])
    create_if_not_exists unique_index(:nexus_gallery_subscriptions, [:user_id, :subject_type, :subject_id])
    create_if_not_exists unique_index(:nexus_gallery_reactions,     [:user_id, :subject_type, :subject_id, :emoji])
  end
end
