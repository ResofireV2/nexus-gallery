defmodule NexusGallery.ApiRouter do
  use Plug.Router

  alias Nexus.Extensions.Permissions
  alias NexusGallery.Tags

  @slug "nexus-gallery"

  plug :match
  plug :dispatch

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp require_permission(conn, key, then_fn) do
    case Permissions.check(@slug, key, conn.assigns[:current_user]) do
      :ok    -> then_fn.(conn)
      :error -> json_resp(conn, 403, %{error: "Access denied"})
    end
  end

  # -------------------------------------------------------------------------
  # Phase 1 health check
  # -------------------------------------------------------------------------

  get "/ping" do
    json_resp(conn, 200, %{ok: true, extension: @slug})
  end

  # -------------------------------------------------------------------------
  # Permissions endpoint
  # Returns resolved permission booleans for the current user.
  # UI uses these for show/hide; server checks remain the authoritative gate.
  # -------------------------------------------------------------------------

  get "/permissions" do
    user = conn.assigns[:current_user]

    keys = [
      "can_view_gallery",
      "can_upload_image",
      "can_upload_video",
      "can_submit_embed",
      "can_create_collection",
      "can_comment",
      "can_rate",
      "can_react",
      "can_subscribe",
      "can_feature_item",
      "can_manage_gallery"
    ]

    resolved =
      Map.new(keys, fn key ->
        {key, Permissions.check(@slug, key, user) == :ok}
      end)

    json_resp(conn, 200, %{permissions: resolved})
  end

  # -------------------------------------------------------------------------
  # Tags — all gated on can_manage_gallery
  # -------------------------------------------------------------------------

  get "/tags" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      tags = Tags.list_tags()
      json_resp(conn, 200, %{tags: Enum.map(tags, &tag_json/1)})
    end)
  end

  post "/tags" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      params = conn.body_params

      attrs = %{
        "name"         => params["name"],
        "slug"         => params["slug"] || NexusGallery.Tag.slugify(params["name"] || ""),
        "color"        => params["color"] || "#7c5cfc",
        "allow_images" => parse_bool(params["allow_images"], true),
        "allow_videos" => parse_bool(params["allow_videos"], true),
        "allow_embeds" => parse_bool(params["allow_embeds"], true),
        "position"     => next_position()
      }

      case Tags.create_tag(attrs) do
        {:ok, tag}          -> json_resp(conn, 201, %{tag: tag_json(tag)})
        {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
      end
    end)
  end

  patch "/tags/:id" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      case Tags.get_tag(conn.params["id"]) do
        nil ->
          json_resp(conn, 404, %{error: "Tag not found"})

        tag ->
          params = conn.body_params

          attrs =
            %{}
            |> maybe_put(params, "name")
            |> maybe_put(params, "color")
            |> maybe_put_bool(params, "allow_images")
            |> maybe_put_bool(params, "allow_videos")
            |> maybe_put_bool(params, "allow_embeds")
            |> maybe_put_slug(params, tag)

          case Tags.update_tag(tag, attrs) do
            {:ok, updated}      -> json_resp(conn, 200, %{tag: tag_json(updated)})
            {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
          end
      end
    end)
  end

  delete "/tags/:id" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      case Tags.get_tag(conn.params["id"]) do
        nil ->
          json_resp(conn, 404, %{error: "Tag not found"})

        tag ->
          case Tags.delete_tag(tag) do
            {:ok, _}            -> json_resp(conn, 200, %{ok: true})
            {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
          end
      end
    end)
  end

  post "/tags/reorder" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      ids = conn.body_params["ids"]

      cond do
        not is_list(ids) ->
          json_resp(conn, 422, %{error: "ids must be an array"})

        not Enum.all?(ids, &is_binary/1) ->
          json_resp(conn, 422, %{error: "all ids must be strings"})

        true ->
          case Tags.reorder_tags(ids) do
            :ok              -> json_resp(conn, 200, %{ok: true})
            {:error, reason} -> json_resp(conn, 500, %{error: inspect(reason)})
          end
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Catch-all
  # -------------------------------------------------------------------------

  match _ do
    json_resp(conn, 404, %{error: "not found"})
  end

  # -------------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------------

  defp tag_json(tag) do
    %{
      id:           tag.id,
      name:         tag.name,
      slug:         tag.slug,
      color:        tag.color,
      position:     tag.position,
      allow_images: tag.allow_images,
      allow_videos: tag.allow_videos,
      allow_embeds: tag.allow_embeds,
      item_count:   tag.item_count,
      inserted_at:  tag.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp next_position do
    import Ecto.Query
    case Nexus.Repo.one(from t in NexusGallery.Tag, select: max(t.position)) do
      nil -> 0
      max -> max + 1
    end
  end

  defp parse_bool(nil, default),    do: default
  defp parse_bool(true, _),         do: true
  defp parse_bool(false, _),        do: false
  defp parse_bool("true", _),       do: true
  defp parse_bool("false", _),      do: false
  defp parse_bool(_, default),      do: default

  defp maybe_put(attrs, params, key) do
    case Map.fetch(params, key) do
      {:ok, val} -> Map.put(attrs, key, val)
      :error     -> attrs
    end
  end

  defp maybe_put_bool(attrs, params, key) do
    case Map.fetch(params, key) do
      {:ok, val} -> Map.put(attrs, key, parse_bool(val, true))
      :error     -> attrs
    end
  end

  defp maybe_put_slug(attrs, params, tag) do
    case Map.fetch(params, "name") do
      {:ok, new_name} when is_binary(new_name) ->
        case Map.fetch(params, "slug") do
          {:ok, s} when is_binary(s) and s != "" ->
            Map.put(attrs, "slug", s)
          _ ->
            if new_name != tag.name do
              Map.put(attrs, "slug", NexusGallery.Tag.slugify(new_name))
            else
              attrs
            end
        end
      _ ->
        attrs
    end
  end
end
