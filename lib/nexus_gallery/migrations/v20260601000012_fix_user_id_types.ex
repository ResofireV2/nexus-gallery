defmodule NexusGallery.Migrations.V20260601000012FixUserIdTypes do
  use Ecto.Migration

  # All six gallery tables had user_id created as :uuid in the Phase 1 migration
  # due to a bug. Nexus users.id is a bigserial integer. These tables are empty
  # so we drop and recreate the columns rather than attempting an in-place cast.
  # source_post_id in nexus_gallery_items has the same problem (posts.id is also integer).

  def change do
    # nexus_gallery_items
    alter table(:nexus_gallery_items) do
      remove :user_id
      remove :source_post_id
    end
    alter table(:nexus_gallery_items) do
      add :user_id,        :integer, null: false, default: 0
      add :source_post_id, :integer
    end
    # Remove the temporary default
    execute "ALTER TABLE nexus_gallery_items ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # nexus_gallery_collections
    alter table(:nexus_gallery_collections) do
      remove :user_id
    end
    alter table(:nexus_gallery_collections) do
      add :user_id, :integer, null: false, default: 0
    end
    execute "ALTER TABLE nexus_gallery_collections ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # nexus_gallery_ratings
    alter table(:nexus_gallery_ratings) do
      remove :user_id
    end
    alter table(:nexus_gallery_ratings) do
      add :user_id, :integer, null: false, default: 0
    end
    execute "ALTER TABLE nexus_gallery_ratings ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # nexus_gallery_comments
    alter table(:nexus_gallery_comments) do
      remove :user_id
    end
    alter table(:nexus_gallery_comments) do
      add :user_id, :integer, null: false, default: 0
    end
    execute "ALTER TABLE nexus_gallery_comments ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # nexus_gallery_subscriptions
    alter table(:nexus_gallery_subscriptions) do
      remove :user_id
    end
    alter table(:nexus_gallery_subscriptions) do
      add :user_id, :integer, null: false, default: 0
    end
    execute "ALTER TABLE nexus_gallery_subscriptions ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # nexus_gallery_reactions
    alter table(:nexus_gallery_reactions) do
      remove :user_id
    end
    alter table(:nexus_gallery_reactions) do
      add :user_id, :integer, null: false, default: 0
    end
    execute "ALTER TABLE nexus_gallery_reactions ALTER COLUMN user_id DROP DEFAULT",
            "SELECT 1"

    # Recreate indexes that involved user_id (dropped automatically with column)
    create index(:nexus_gallery_items,         [:user_id])
    create index(:nexus_gallery_collections,   [:user_id])
    create unique_index(:nexus_gallery_ratings,       [:user_id, :subject_type, :subject_id])
    create unique_index(:nexus_gallery_subscriptions, [:user_id, :subject_type, :subject_id])
    create unique_index(:nexus_gallery_reactions,     [:user_id, :subject_type, :subject_id, :emoji])
  end
end
