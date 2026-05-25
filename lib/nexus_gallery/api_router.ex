defmodule NexusGallery.ApiRouter do
  use Plug.Router

  import Ecto.Query

  alias Nexus.Extensions.Permissions
  alias Nexus.Extensions
  alias NexusGallery.{Tags, Items}

  @slug "nexus-gallery"

  plug :match
  plug :dispatch

  # Wrap the entire router in a rescue so every unhandled exception
  # returns a JSON error body rather than an opaque 500 from ExtensionRouter.
  def call(conn, opts) do
    try do
      super(conn, opts)
    rescue
      e -> json_resp(conn, 500, %{error: inspect(e)})
    end
  end

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
      nil -> json_resp(conn, 401, %{error: "Login required"})
      _   -> then_fn.(conn)
    end
  end

  defp settings do
    case Extensions.get_extension_by_slug(@slug) do
      nil -> %{}
      ext -> ext.settings || %{}
    end
  end

  defp parse_int(nil, default),          do: default
  defp parse_int(v, default) when is_integer(v), do: v
  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(_, default), do: default

  # -------------------------------------------------------------------------
  # Health check
  # -------------------------------------------------------------------------

  get "/ping" do
    json_resp(conn, 200, %{ok: true, extension: @slug})
  end

  # -------------------------------------------------------------------------
  # Permissions
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
    s = settings()
    json_resp(conn, 200, %{
      permissions:    resolved,
      videos_enabled: s["videos_enabled"] == true,
      embeds_enabled: s["embeds_enabled"] != false
    })
  end

  # -------------------------------------------------------------------------
  # Tags
  # -------------------------------------------------------------------------

  get "/tags" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      tags = Tags.list_tags()
      json_resp(conn, 200, %{tags: Enum.map(tags, &tag_json/1)})
    end)
  end

  # Public tag list for the gallery browse page filter chips
  get "/tags/public" do
    require_permission(conn, "can_view_gallery", fn conn ->
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
        not is_list(ids)               -> json_resp(conn, 422, %{error: "ids must be an array"})
        not Enum.all?(ids, &is_binary/1) -> json_resp(conn, 422, %{error: "all ids must be strings"})
        true ->
          case Tags.reorder_tags(ids) do
            :ok              -> json_resp(conn, 200, %{ok: true})
            {:error, reason} -> json_resp(conn, 500, %{error: inspect(reason)})
          end
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Items — list (Phase 4)
  # -------------------------------------------------------------------------

  get "/items" do
    require_permission(conn, "can_view_gallery", fn conn ->
      params   = conn.query_params
      s        = settings()
      per_page = parse_int(params["per_page"], parse_int(s["items_per_page"], 36))

      opts = [
        page:       parse_int(params["page"], 1),
        per_page:   per_page,
        sort:       params["sort"] || "newest",
        tag_slug:   params["tag"],
        media_type: params["type"],
        user_id:    params["user_id"] && parse_int(params["user_id"], nil),
        search:     params["search"],
      ]

      {items, total} = Items.list_items(opts)
      per = Keyword.get(opts, :per_page)
      page = Keyword.get(opts, :page)

      json_resp(conn, 200, %{
        items:      Enum.map(items, &browse_item_json/1),
        total:      total,
        page:       page,
        per_page:   per,
        total_pages: ceil(total / per)
      })
    end)
  end

  # -------------------------------------------------------------------------
  # Items — single, create, update, delete (Phase 3)
  # -------------------------------------------------------------------------

  post "/items/draft" do
    require_permission(conn, "can_upload_image", fn conn ->
      user       = conn.assigns.current_user
      media_type = conn.body_params["media_type"] || "image"
      s          = settings()

      if media_type == "video" and s["videos_enabled"] != true do
        json_resp(conn, 403, %{error: "Video uploads are not enabled on this forum"})
      else
        case Items.create_draft(user.id, media_type) do
          {:ok, item}         -> json_resp(conn, 201, %{id: uuid_str(item.id), media_type: item.media_type})
          {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
        end
      end
    end)
  end

  get "/items/:id" do
    try do
      require_permission(conn, "can_view_gallery", fn conn ->
        user = conn.assigns[:current_user]
        case Items.get_item_with_tags(conn.params["id"]) do
          nil  -> json_resp(conn, 404, %{error: "Item not found"})
          item ->
            owner_or_admin = user && (user.id == item.user_id || user.role in ["admin", "moderator"])
            if item.is_draft and not owner_or_admin do
              json_resp(conn, 404, %{error: "Item not found"})
            else
              json_resp(conn, 200, %{item: item_json(item, user)})
            end
        end
      end)
    rescue
      e -> json_resp(conn, 500, %{error: inspect(e)})
    end
  end

  patch "/items/:id" do
    try do
      require_auth(conn, fn conn ->
        user = conn.assigns.current_user
        case Items.get_item(conn.params["id"]) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless user.id == item.user_id || user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            params   = conn.body_params
            tag_ids  = params["tag_ids"]
            s        = settings()
            max_tags = parse_int(s["max_tags_per_item"], 5)

            tag_ids_validated =
              cond do
                is_nil(tag_ids)              -> []
                not is_list(tag_ids)         -> []
                length(tag_ids) > max_tags   -> Enum.take(tag_ids, max_tags)
                true                         -> tag_ids
              end

            attrs =
              %{}
              |> maybe_put(params, "title")
              |> maybe_put(params, "description")
              |> maybe_put(params, "embed_url")
              |> maybe_put(params, "file_url")
              |> maybe_put(params, "original_url")
              |> maybe_put(params, "thumbnail_url")
              |> maybe_put(params, "width")
              |> maybe_put(params, "height")
              |> maybe_put(params, "upload_id")
              |> (fn a ->
                case Map.fetch(params, "is_draft") do
                  {:ok, v} -> Map.put(a, "is_draft", parse_bool(v, true))
                  :error   -> a
                end
              end).()

            case Items.update_and_publish(item, attrs, tag_ids_validated) do
              {:ok, updated}      -> json_resp(conn, 200, %{item: item_json(updated, user)})
              {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
            end
          end
      end
    end)
    rescue
      e -> json_resp(conn, 500, %{error: inspect(e)})
    end
  end


  post "/items/:id/feature" do
    require_permission(conn, "can_feature_item", fn conn ->
      case Items.get_item(conn.params["id"]) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          new_val = not item.is_featured
          id_str = uuid_str(item.id)
          case Nexus.Repo.update_all(
            Ecto.Query.from(i in NexusGallery.Item,
              where: i.id == type(^id_str, :binary_id)),
            set: [is_featured: new_val]
          ) do
            {1, _} -> json_resp(conn, 200, %{is_featured: new_val})
            _      -> json_resp(conn, 500, %{error: "Update failed"})
          end
      end
    end)
  end

  delete "/items/:id" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      case Items.get_item(conn.params["id"]) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless user.id == item.user_id || user.role in ["admin", "moderator"] do
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
  # Stats and widgets (Phase 4)
  # -------------------------------------------------------------------------

  get "/stats" do
    require_permission(conn, "can_view_gallery", fn conn ->
      json_resp(conn, 200, Items.stats())
    end)
  end

  get "/top-rated" do
    require_permission(conn, "can_view_gallery", fn conn ->
      limit = parse_int(conn.query_params["limit"], 4)
      items = Items.top_rated(limit)
      json_resp(conn, 200, %{items: Enum.map(items, &widget_item_json/1)})
    end)
  end

  get "/top-uploaders" do
    require_permission(conn, "can_view_gallery", fn conn ->
      limit = parse_int(conn.query_params["limit"], 4)
      rows = Items.top_uploaders(limit)
      json_resp(conn, 200, %{uploaders: Enum.map(rows, fn r ->
        %{user: r.user, count: r.count}
      end)})
    end)
  end

  # -------------------------------------------------------------------------
  # Catch-all
  # -------------------------------------------------------------------------

  match _ do
    json_resp(conn, 404, %{error: "not found"})
  end

  # -------------------------------------------------------------------------
  # JSON serialisers
  # -------------------------------------------------------------------------

  # Full item JSON — used for detail page and metadata form
  defp item_json(item, current_user) do
    tags = Map.get(item, :tags, [])
    user = Map.get(item, :user)
    %{
      id:            item.id,
      user_id:       item.user_id,
      user:          user,
      title:         item.title,
      description:   item.description,
      media_type:    item.media_type,
      is_draft:      item.is_draft,
      is_featured:   item.is_featured,
      view_count:    item.view_count,
      file_url:      item.file_url,
      original_url:  item.original_url,
      thumbnail_url: item.thumbnail_url,
      embed_url:     item.embed_url,
      width:         item.width,
      height:        item.height,
      upload_id:     item.upload_id,
      tags:          Enum.map(tags, &tag_json/1),
      can_edit:      can_edit?(item, current_user),
      can_delete:    can_delete?(item, current_user),
      can_feature:   can_feature?(current_user),
      inserted_at:   item.inserted_at
    }
  end

  # Compact item JSON for browse grid cards
  defp browse_item_json(item) do
    user = Map.get(item, :user)
    %{
      id:            item.id,
      user_id:       item.user_id,
      user:          user,
      title:         item.title,
      media_type:    item.media_type,
      is_featured:   item.is_featured,
      file_url:      item.file_url,
      thumbnail_url: item.thumbnail_url,
      embed_url:     item.embed_url,
      width:         item.width,
      height:        item.height,
      view_count:    item.view_count,
      inserted_at:   item.inserted_at
    }
  end

  # Minimal item JSON for right widgets
  defp widget_item_json(item) do
    %{
      id:            item.id,
      title:         item.title,
      thumbnail_url: item.thumbnail_url,
      file_url:      item.file_url,
      view_count:    item.view_count
    }
  end

  defp tag_json(tag) do
    %{
      id:           uuid_str(tag.id),
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

  defp can_edit?(_item, nil),  do: false
  defp can_edit?(item, user),  do: user.id == item.user_id || user.role in ["admin", "moderator"]

  defp can_delete?(_item, nil), do: false
  defp can_delete?(item, user), do: user.id == item.user_id || user.role in ["admin", "moderator"]

  defp can_feature?(nil),  do: false
  defp can_feature?(user), do: user.role in ["admin", "moderator"]

  # -------------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------------

  # Convert a 16-byte binary UUID to string form for JSON encoding.
  # Ecto stores :binary_id fields as raw binaries — Jason cannot encode them.
  defp uuid_str(nil), do: nil
  defp uuid_str(bin) when is_binary(bin) and byte_size(bin) == 16 do
    case Ecto.UUID.load(bin) do
      {:ok, str} -> str
      :error     -> nil
    end
  end
  defp uuid_str(str) when is_binary(str), do: str

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
