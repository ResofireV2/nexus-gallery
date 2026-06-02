defmodule NexusGallery.Migrations.V12FixUserIdTypes do
  use Ecto.Migration

  # All six gallery tables had user_id created as :uuid in the Phase 1 migration
  # due to a bug. Nexus users.id is a bigserial integer. These tables are empty
  # so we drop and recreate the columns rather than attempting an in-place cast.
  # source_post_id in nexus_gallery_items has the same problem (posts.id is also integer).
  #
  # Each block uses execute with a DO $$ ... END $$ guard so the migration is
  # idempotent: if user_id is already integer type (already ran), it skips cleanly.

  def change do
    # nexus_gallery_items — user_id and source_post_id
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_items' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_items DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_items DROP COLUMN source_post_id;
        ALTER TABLE nexus_gallery_items ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_items ADD COLUMN source_post_id integer;
        ALTER TABLE nexus_gallery_items ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # nexus_gallery_collections
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_collections' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_collections DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_collections ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_collections ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # nexus_gallery_ratings
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_ratings' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_ratings DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_ratings ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_ratings ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # nexus_gallery_comments
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_comments' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_comments DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_comments ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_comments ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # nexus_gallery_subscriptions
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_subscriptions' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_subscriptions DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_subscriptions ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_subscriptions ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # nexus_gallery_reactions
    execute """
    DO $$ BEGIN
      IF (SELECT data_type FROM information_schema.columns
          WHERE table_name = 'nexus_gallery_reactions' AND column_name = 'user_id') = 'uuid' THEN
        ALTER TABLE nexus_gallery_reactions DROP COLUMN user_id;
        ALTER TABLE nexus_gallery_reactions ADD COLUMN user_id integer NOT NULL DEFAULT 0;
        ALTER TABLE nexus_gallery_reactions ALTER COLUMN user_id DROP DEFAULT;
      END IF;
    END $$;
    """, "SELECT 1"

    # Recreate indexes that involved user_id (dropped automatically with column).
    # create_if_not_exists handles the case where they already exist.
    create_if_not_exists index(:nexus_gallery_items,        [:user_id])
    create_if_not_exists index(:nexus_gallery_collections,  [:user_id])
    create_if_not_exists unique_index(:nexus_gallery_ratings,       [:user_id, :subject_type, :subject_id])
    create_if_not_exists unique_index(:nexus_gallery_subscriptions, [:user_id, :subject_type, :subject_id])
    create_if_not_exists unique_index(:nexus_gallery_reactions,     [:user_id, :subject_type, :subject_id, :emoji])
  end
end
