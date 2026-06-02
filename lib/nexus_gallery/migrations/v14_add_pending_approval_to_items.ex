defmodule NexusGallery.Migrations.V14AddPendingApprovalToItems do
  use Ecto.Migration

  def change do
    alter table(:nexus_gallery_items) do
      add :pending_approval, :boolean, null: false, default: false
    end

    create index(:nexus_gallery_items, [:pending_approval])
  end
end
