defmodule NexusGallery.ApiRouter do
  use Plug.Router

  import Ecto.Query

  alias Nexus.Extensions.Permissions
  alias Nexus.Extensions
  alias NexusGallery.{Tags, Items}

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

  defp require_auth(conn, then_fn) do
    case conn.assigns[:current_user] do
      nil  -> json_resp(conn, 401, %{error: "Login required"})
      _    -> then_fn.(conn)
    end
  end

  defp settings do
    case Extensions.get_extension_by_slug(@slug) do
      nil -> %{}
      ext -> ext.settings || %{}
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
  # -------------------------------------------------------------------------

  get "/permissions" do
    user = conn.assigns[:current_user]

    keys = [
      "can_view_gallery", "can_upload_image", "can_upload_video",
      "can_submit_embed", "can_create_collection", "can_comment",
      "can_rate", "can_react", "can_subscribe",
      "can_feature_item", "can_manage_gallery"
    ]

    resolved = Map.new(keys, fn key ->
      {key, Permissions.check(@slug, key, user) == :ok}
    end)

    # Include relevant settings the frontend needs for show/hide decisions
    s = settings()
    json_resp(conn, 200, %{
      permissions:    resolved,
      videos_enabled: s["videos_enabled"] == true,
      embeds_enabled: s["embeds_enabled"] != false
    })
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
        nil -> json_resp(conn, 404, %{error: "Tag not found"})
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
        nil -> json_resp(conn, 404, %{error: "Tag not found"})
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
  # Items — Phase 3
  # -------------------------------------------------------------------------

  # POST /items/draft
  # Creates an empty draft item and returns its id.
  # Called before file upload so we have a record_id for Nexus.
  post "/items/draft" do
    require_permission(conn, "can_upload_image", fn conn ->
      user       = conn.assigns.current_user
      media_type = conn.body_params["media_type"] || "image"
      s          = settings()

      # Gate video uploads behind the videos_enabled setting
      if media_type == "video" and s["videos_enabled"] != true do
        json_resp(conn, 403, %{error: "Video uploads are not enabled on this forum"})
      else
        case Items.create_draft(user.id, media_type) do
          {:ok, item}         -> json_resp(conn, 201, %{id: item.id, media_type: item.media_type})
          {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
        end
      end
    end)
  end

  # GET /items/:id
  # Returns a single item. Owner or admin can see drafts; others cannot.
  get "/items/:id" do
    require_permission(conn, "can_view_gallery", fn conn ->
      user = conn.assigns[:current_user]

      case Items.get_item_with_tags(conn.params["id"]) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          owner_or_admin = user && (to_string(user.id) == to_string(item.user_id) || user.role in ["admin", "moderator"])

          if item.is_draft and not owner_or_admin do
            json_resp(conn, 404, %{error: "Item not found"})
          else
            json_resp(conn, 200, %{item: item_json(item, user)})
          end
      end
    end)
  end

  # PATCH /items/:id
  # Saves metadata (title, description, tags) and optionally publishes.
  # Called from the /new/:uuid metadata form after upload completes.
  patch "/items/:id" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user

      case Items.get_item(conn.params["id"]) do
        nil -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless to_string(user.id) == to_string(item.user_id) || user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            params   = conn.body_params
            tag_ids  = params["tag_ids"]
            s        = settings()
            max_tags = (s["max_tags_per_item"] || 5) |> trunc()

            tag_ids_validated =
              cond do
                is_nil(tag_ids)         -> []
                not is_list(tag_ids)    -> []
                length(tag_ids) > max_tags -> Enum.take(tag_ids, max_tags)
                true                    -> tag_ids
              end

            attrs = %{
              "title"        => params["title"],
              "description"  => params["description"],
              "is_draft"     => parse_bool(params["is_draft"], true),
              "file_url"     => params["file_url"],
              "original_url" => params["original_url"],
              "thumbnail_url"=> params["thumbnail_url"],
              "width"        => params["width"],
              "height"       => params["height"],
              "upload_id"    => params["upload_id"],
              "embed_url"    => params["embed_url"]
            }
            |> Enum.reject(fn {_, v} -> is_nil(v) end)
            |> Map.new()

            case Items.update_and_publish(item, attrs, tag_ids_validated) do
              {:ok, updated}      -> json_resp(conn, 200, %{item: item_json(updated, user)})
              {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
            end
          end
      end
    end)
  end

  # DELETE /items/:id
  # Owner or admin only.
  delete "/items/:id" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user

      case Items.get_item(conn.params["id"]) do
        nil -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless to_string(user.id) == to_string(item.user_id) || user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            case Items.delete_item(item) do
              :ok              -> json_resp(conn, 200, %{ok: true})
              {:error, reason} -> json_resp(conn, 500, %{error: inspect(reason)})
            end
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

  defp item_json(item, current_user) do
    tags = Map.get(item, :tags, [])

    %{
      id:           item.id,
      user_id:      item.user_id,
      title:        item.title,
      description:  item.description,
      media_type:   item.media_type,
      is_draft:     item.is_draft,
      is_featured:  item.is_featured,
      view_count:   item.view_count,
      file_url:     item.file_url,
      original_url: item.original_url,
      thumbnail_url: item.thumbnail_url,
      embed_url:    item.embed_url,
      width:        item.width,
      height:       item.height,
      upload_id:    item.upload_id,
      tags:         Enum.map(tags, &tag_json/1),
      can_edit:     can_edit?(item, current_user),
      can_delete:   can_delete?(item, current_user),
      can_feature:  can_feature?(current_user),
      inserted_at:  item.inserted_at
    }
  end

  defp can_edit?(item, nil), do: false
  defp can_edit?(item, user) do
    to_string(user.id) == to_string(item.user_id) || user.role in ["admin", "moderator"]
  end

  defp can_delete?(item, nil), do: false
  defp can_delete?(item, user) do
    to_string(user.id) == to_string(item.user_id) || user.role in ["admin", "moderator"]
  end

  defp can_feature?(_item \\ nil, nil), do: false
  defp can_feature?(_item \\ nil, user), do: user.role in ["admin", "moderator"]

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
          {:ok, s} when is_binary(s) and s != "" -> Map.put(attrs, "slug", s)
          _ ->
            if new_name != tag.name do
              Map.put(attrs, "slug", NexusGallery.Tag.slugify(new_name))
            else
              attrs
            end
        end
      _ -> attrs
    end
  end
end
