defmodule NexusGallery.Tags do
  import Ecto.Query
  alias Nexus.Repo
  alias NexusGallery.Tag

  defp uuid_bin(nil), do: nil
  defp uuid_bin(bin) when is_binary(bin) and byte_size(bin) == 16, do: bin
  defp uuid_bin(str) when is_binary(str) do
    case Ecto.UUID.dump(str) do
      {:ok, bin} -> bin
      :error     -> nil
    end
  end

  @doc "Returns all tags ordered by position ascending."
  def list_tags do
    from(t in Tag, order_by: [asc: t.position, asc: t.inserted_at])
    |> Repo.all()
  end

  @doc "Returns a single tag by id (string UUID), or nil."
  def get_tag(id) do
    Repo.one(from t in Tag, where: t.id == type(^uuid_bin(id), :uuid))
  end

  @doc "Returns a single tag by slug, or nil."
  def get_tag_by_slug(slug) do
    Repo.get_by(Tag, slug: slug)
  end

  @doc "Creates a tag. Returns {:ok, tag} or {:error, changeset}."
  def create_tag(attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a tag. Returns {:ok, tag} or {:error, changeset}."
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a tag. Returns {:ok, tag} or {:error, changeset}."
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Reorders tags by updating their position field.
  Accepts an ordered list of tag id strings.
  Returns :ok or {:error, reason}.
  """
  def reorder_tags(ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(t in Tag, where: t.id == type(^uuid_bin(id), :uuid))
        |> Repo.update_all(set: [position: index])
      end)
    end)
    |> case do
      {:ok, _}         -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
