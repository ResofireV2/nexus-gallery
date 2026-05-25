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
      permissions:       resolved,
      videos_enabled:    s["videos_enabled"] == true,
      embeds_enabled:    s["embeds_enabled"] != false,
      ratings_enabled:       s["ratings_enabled"] == true,
      reactions_enabled:     s["reactions_enabled"] == true,
      block_self_ratings:    s["block_self_ratings"] == true,
      block_self_reactions:  s["block_self_reactions"] == true,
      comments_enabled:      s["comments_enabled"] == true
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


  # -------------------------------------------------------------------------
  # Ratings
  # -------------------------------------------------------------------------

  get "/items/:id/ratings" do
    require_permission(conn, "can_view_gallery", fn conn ->
      user = conn.assigns[:current_user]
      item_id_str = conn.params["id"]
      case Ecto.UUID.dump(item_id_str) do
        {:ok, id_bin} ->
          stats = rating_stats(id_bin, "item")
          my_rating =
            if user do
              case Nexus.Repo.one(
                Ecto.Query.from r in "nexus_gallery_ratings",
                  where: r.user_id == ^user.id
                    and r.subject_type == "item"
                    and fragment("? = ?::uuid", r.subject_id, type(^item_id_str, :string)),
                  select: r.value
              ) do
                nil -> nil
                v   -> v
              end
            end
          json_resp(conn, 200, Map.put(stats, :my_rating, my_rating))
        :error ->
          json_resp(conn, 404, %{error: "Item not found"})
      end
    end)
  end

  post "/items/:id/ratings" do
    require_permission(conn, "can_rate", fn conn ->
      user = conn.assigns.current_user
      item_id_str = conn.params["id"]
      value = parse_int(conn.body_params["value"], nil)

      cond do
        is_nil(value) or value < 1 or value > 5 ->
          json_resp(conn, 422, %{error: "value must be an integer between 1 and 5"})
        true ->
          case Ecto.UUID.dump(item_id_str) do
            {:ok, id_bin} ->
              s = settings()
              block_self = s["block_self_ratings"] == true
              item_owner = Nexus.Repo.one(
                Ecto.Query.from i in NexusGallery.Item,
                  where: i.id == type(^item_id_str, :binary_id),
                  select: i.user_id
              )
              if block_self and item_owner == user.id do
                json_resp(conn, 403, %{error: "You cannot rate your own items"})
              else
              # Delete existing rating from this user for this item
              Nexus.Repo.delete_all(
                Ecto.Query.from r in "nexus_gallery_ratings",
                  where: r.user_id == ^user.id
                    and r.subject_type == "item"
                    and r.subject_id == ^id_bin
              )
              # Insert new rating
              {:ok, rating_id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              Nexus.Repo.insert_all("nexus_gallery_ratings", [%{
                id:           rating_id_bin,
                user_id:      user.id,
                subject_type: "item",
                subject_id:   id_bin,
                value:        value,
                inserted_at:  now,
                updated_at:   now
              }])
              stats = rating_stats(id_bin, "item")
              json_resp(conn, 200, Map.put(stats, :my_rating, value))
              end  # end self-block else
            :error ->
              json_resp(conn, 404, %{error: "Item not found"})
          end
      end
    end)
  end

  delete "/items/:id/ratings" do
    require_permission(conn, "can_rate", fn conn ->
      user = conn.assigns.current_user
      item_id_str = conn.params["id"]
      case Ecto.UUID.dump(item_id_str) do
        {:ok, id_bin} ->
          Nexus.Repo.delete_all(
            Ecto.Query.from r in "nexus_gallery_ratings",
              where: r.user_id == ^user.id
                and r.subject_type == "item"
                and r.subject_id == ^id_bin
          )
          stats = rating_stats(id_bin, "item")
          json_resp(conn, 200, Map.put(stats, :my_rating, nil))
        :error ->
          json_resp(conn, 404, %{error: "Item not found"})
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Reactions
  # -------------------------------------------------------------------------

  get "/items/:id/reactions" do
    require_permission(conn, "can_view_gallery", fn conn ->
      user = conn.assigns[:current_user]
      item_id_str = conn.params["id"]
      case Ecto.UUID.dump(item_id_str) do
        {:ok, id_bin} ->
          counts = reaction_counts(id_bin, "item")
          mine =
            if user do
              Nexus.Repo.all(
                Ecto.Query.from r in "nexus_gallery_reactions",
                  where: r.user_id == ^user.id
                    and r.subject_type == "item"
                    and r.subject_id == ^id_bin,
                  select: r.emoji
              )
            else
              []
            end
          json_resp(conn, 200, %{counts: counts, mine: mine})
        :error ->
          json_resp(conn, 404, %{error: "Item not found"})
      end
    end)
  end

  post "/items/:id/reactions" do
    require_permission(conn, "can_react", fn conn ->
      user = conn.assigns.current_user
      item_id_str = conn.params["id"]
      emoji = conn.body_params["emoji"]

      if is_nil(emoji) or emoji == "" do
        json_resp(conn, 422, %{error: "emoji is required"})
      else
        case Ecto.UUID.dump(item_id_str) do
          {:ok, id_bin} ->
            s = settings()
            # Check self-reaction block (default: on)
            block_self = s["block_self_reactions"] == true
            item_owner = Nexus.Repo.one(
              Ecto.Query.from i in NexusGallery.Item,
                where: i.id == type(^item_id_str, :binary_id),
                select: i.user_id
            )
            if block_self and item_owner == user.id do
              json_resp(conn, 403, %{error: "You cannot react to your own items"})
            else
              # Exclusive reactions: one per user per item.
              # If user already reacted with THIS emoji, toggle it off.
              # If user reacted with a DIFFERENT emoji, replace it.
              current_emoji = Nexus.Repo.one(
                Ecto.Query.from(r in "nexus_gallery_reactions",
                  where: r.user_id == ^user.id
                    and r.subject_type == "item"
                    and r.subject_id == ^id_bin,
                  select: r.emoji)
              )
              cond do
                current_emoji == emoji ->
                  # Same emoji clicked — toggle off
                  Nexus.Repo.delete_all(
                    Ecto.Query.from r in "nexus_gallery_reactions",
                      where: r.user_id == ^user.id
                        and r.subject_type == "item"
                        and r.subject_id == ^id_bin
                  )
                current_emoji != nil ->
                  # Different emoji — replace existing
                  Nexus.Repo.delete_all(
                    Ecto.Query.from r in "nexus_gallery_reactions",
                      where: r.user_id == ^user.id
                        and r.subject_type == "item"
                        and r.subject_id == ^id_bin
                  )
                  {:ok, reaction_id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
                  now = DateTime.utc_now() |> DateTime.truncate(:second)
                  Nexus.Repo.insert_all("nexus_gallery_reactions", [%{
                    id:           reaction_id_bin,
                    user_id:      user.id,
                    subject_type: "item",
                    subject_id:   id_bin,
                    emoji:        emoji,
                    inserted_at:  now,
                    updated_at:   now
                  }])
                true ->
                  # No existing reaction — insert new
                  {:ok, reaction_id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
                  now = DateTime.utc_now() |> DateTime.truncate(:second)
                  Nexus.Repo.insert_all("nexus_gallery_reactions", [%{
                    id:           reaction_id_bin,
                    user_id:      user.id,
                    subject_type: "item",
                    subject_id:   id_bin,
                    emoji:        emoji,
                    inserted_at:  now,
                    updated_at:   now
                  }])
              end
              counts = reaction_counts(id_bin, "item")
              mine =
                Nexus.Repo.all(
                  Ecto.Query.from r in "nexus_gallery_reactions",
                    where: r.user_id == ^user.id
                      and r.subject_type == "item"
                      and r.subject_id == ^id_bin,
                    select: r.emoji
                )
              json_resp(conn, 200, %{counts: counts, mine: mine})
            end  # end self-block else
          :error ->
            json_resp(conn, 404, %{error: "Item not found"})
        end
      end
    end)
  end


  # -------------------------------------------------------------------------
  # Comments
  # -------------------------------------------------------------------------

  get "/items/:id/comments" do
    require_permission(conn, "can_view_gallery", fn conn ->
      user = conn.assigns[:current_user]
      item_id_str = conn.params["id"]
      page     = parse_int(conn.query_params["page"], 1) |> max(1)
      per_page = 20
      offset   = (page - 1) * per_page

      case Ecto.UUID.dump(item_id_str) do
        {:ok, id_bin} ->
          total = Nexus.Repo.aggregate(
            Ecto.Query.from(c in "nexus_gallery_comments",
              where: c.subject_type == "item" and c.subject_id == ^id_bin),
            :count, :id
          )
          rows = Nexus.Repo.all(
            Ecto.Query.from c in "nexus_gallery_comments",
              where: c.subject_type == "item" and c.subject_id == ^id_bin,
              order_by: [asc: c.inserted_at],
              limit:  ^per_page,
              offset: ^offset,
              select: %{
                id:          fragment("?::text", c.id),
                user_id:     c.user_id,
                body:        c.body,
                inserted_at: c.inserted_at
              }
          )
          user_ids = rows |> Enum.map(& &1.user_id) |> Enum.uniq()
          users =
            if user_ids == [] do
              %{}
            else
              Nexus.Repo.all(
                Ecto.Query.from u in "users",
                  where: u.id in ^user_ids,
                  select: %{
                    id:         u.id,
                    username:   fragment("?::text", u.username),
                    avatar_url: u.avatar_url
                  }
              ) |> Map.new(fn u -> {u.id, u} end)
            end
          comments = Enum.map(rows, fn c ->
            can_delete = user != nil and (
              user.id == c.user_id or user.role in ["admin", "moderator"]
            )
            c
            |> Map.put(:user, Map.get(users, c.user_id))
            |> Map.put(:can_delete, can_delete)
          end)
          json_resp(conn, 200, %{
            comments:    comments,
            total:       total,
            page:        page,
            total_pages: ceil(total / per_page)
          })
        :error ->
          json_resp(conn, 404, %{error: "Item not found"})
      end
    end)
  end

  post "/items/:id/comments" do
    require_permission(conn, "can_comment", fn conn ->
      user = conn.assigns.current_user
      item_id_str = conn.params["id"]
      body = conn.body_params["body"]

      cond do
        is_nil(body) or String.trim(body) == "" ->
          json_resp(conn, 422, %{error: "Comment body cannot be blank"})
        String.length(body) > 10_000 ->
          json_resp(conn, 422, %{error: "Comment is too long (max 10,000 characters)"})
        true ->
          case Ecto.UUID.dump(item_id_str) do
            {:ok, id_bin} ->
              {:ok, comment_id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              Nexus.Repo.insert_all("nexus_gallery_comments", [%{
                id:           comment_id_bin,
                user_id:      user.id,
                subject_type: "item",
                subject_id:   id_bin,
                body:         String.trim(body),
                inserted_at:  now,
                updated_at:   now
              }])
              comment_id_str = Ecto.UUID.load!(comment_id_bin)
              user_map = %{id: user.id, username: user.username, avatar_url: user.avatar_url}
              json_resp(conn, 201, %{comment: %{
                id:          comment_id_str,
                user_id:     user.id,
                user:        user_map,
                body:        String.trim(body),
                inserted_at: now,
                can_delete:  true
              }})
            :error ->
              json_resp(conn, 404, %{error: "Item not found"})
          end
      end
    end)
  end

  delete "/items/:id/comments/:comment_id" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      comment_id_str = conn.params["comment_id"]
      case Ecto.UUID.dump(comment_id_str) do
        {:ok, comment_id_bin} ->
          comment_owner = Nexus.Repo.one(
            Ecto.Query.from c in "nexus_gallery_comments",
              where: c.id == ^comment_id_bin,
              select: c.user_id
          )
          cond do
            is_nil(comment_owner) ->
              json_resp(conn, 404, %{error: "Comment not found"})
            comment_owner != user.id and user.role not in ["admin", "moderator"] ->
              json_resp(conn, 403, %{error: "Access denied"})
            true ->
              Nexus.Repo.delete_all(
                Ecto.Query.from c in "nexus_gallery_comments",
                  where: c.id == ^comment_id_bin
              )
              json_resp(conn, 200, %{ok: true})
          end
        :error ->
          json_resp(conn, 404, %{error: "Comment not found"})
      end
    end)
  end

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
      inserted_at:  Map.get(tag, :inserted_at)
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

  defp rating_stats(subject_id_bin, subject_type) do
    result = Nexus.Repo.one(
      from r in "nexus_gallery_ratings",
        where: r.subject_type == ^subject_type and r.subject_id == ^subject_id_bin,
        select: %{count: count(r.id), avg: fragment("ROUND(AVG(?)::numeric, 1)", r.value)}
    )
    count = result[:count] || 0
    avg   = case result[:avg] do
      nil -> nil
      %Decimal{} = d -> Decimal.to_float(d)
      f when is_float(f) -> Float.round(f, 1)
      other -> other
    end
    %{count: count, avg: avg}
  end

  defp reaction_counts(subject_id_bin, subject_type) do
    rows = Nexus.Repo.all(
      from r in "nexus_gallery_reactions",
        where: r.subject_type == ^subject_type and r.subject_id == ^subject_id_bin,
        group_by: r.emoji,
        select: {r.emoji, count(r.id)}
    )
    Map.new(rows, fn {emoji, count} -> {emoji, count} end)
  end

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
