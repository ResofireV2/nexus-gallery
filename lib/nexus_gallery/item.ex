defmodule NexusGallery.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_media_types ~w(image video embed)

  schema "nexus_gallery_items" do
    field :user_id,        :integer
    field :title,          :string
    field :description,    :string
    field :media_type,     :string, default: "image"
    field :is_draft,       :boolean, default: true
    field :is_featured,    :boolean, default: false
    field :view_count,     :integer, default: 0
    field :embed_url,      :string
    field :file_url,       :string
    field :original_url,   :string
    field :thumbnail_url,  :string
    field :width,          :integer
    field :height,         :integer
    field :upload_id,      :binary_id
    field :source_post_id, :integer
    timestamps(type: :utc_datetime)
  end

  def draft_changeset(item, attrs) do
    item
    |> cast(attrs, [:user_id, :media_type])
    |> validate_required([:user_id, :media_type])
    |> validate_inclusion(:media_type, @valid_media_types)
  end

  def upload_changeset(item, attrs) do
    item
    |> cast(attrs, [:file_url, :original_url, :thumbnail_url, :width, :height, :upload_id])
  end

  def publish_changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :description, :is_draft, :embed_url,
                    :file_url, :original_url, :thumbnail_url,
                    :width, :height, :upload_id])
    |> validate_length(:title, max: 200)
  end
end
