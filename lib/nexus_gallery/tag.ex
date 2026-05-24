defmodule NexusGallery.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "nexus_gallery_tags" do
    field :name,          :string
    field :slug,          :string
    field :color,         :string, default: "#7c5cfc"
    field :position,      :integer, default: 0
    field :allow_images,  :boolean, default: true
    field :allow_videos,  :boolean, default: true
    field :allow_embeds,  :boolean, default: true
    field :item_count,    :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :slug, :color, :position, :allow_images, :allow_videos, :allow_embeds])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_length(:slug, min: 1, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must be lowercase letters, numbers, and hyphens only")
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a valid hex color")
    |> unique_constraint(:slug)
  end

  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
