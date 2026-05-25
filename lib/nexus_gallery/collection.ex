defmodule NexusGallery.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "nexus_gallery_collections" do
    field :user_id,     :integer
    field :title,       :string
    field :slug,        :string
    field :description, :string
    field :cover_url,   :string
    field :is_draft,    :boolean, default: true
    field :is_featured, :boolean, default: false
    field :item_count,  :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def create_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:user_id, :title, :slug, :description, :is_draft])
    |> validate_required([:user_id, :title, :slug])
    |> validate_length(:title, max: 200)
    |> unique_constraint(:slug)
  end

  def update_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:title, :slug, :description, :cover_url, :is_draft])
    |> validate_length(:title, max: 200)
    |> unique_constraint(:slug)
  end

  def slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
