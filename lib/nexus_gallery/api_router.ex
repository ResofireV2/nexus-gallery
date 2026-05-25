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
      videos_enabled:    parse_bool(s["videos_enabled"], false),
      embeds_enabled:    s["embeds_enabled"] != false,
      harvest_enabled:   parse_bool(s["harvest_enabled"], false),
      ratings_enabled:       s["ratings_enabled"] == true,
      reactions_enabled:     s["reactions_enabled"] == true,
      block_self_ratings:    s["block_self_ratings"] == true,
      block_self_reactions:  s["block_self_reactions"] == true,
      comments_enabled:      s["comments_enabled"] == true,
      max_collection_size:   parse_int(s["max_collection_size"], 100)
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

      if media_type == "video" and not parse_bool(s["videos_enabled"], false) do
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

            # If moderation queue is enabled and a non-admin is trying to publish,
            # intercept: set pending_approval=true and keep is_draft=true.
            is_admin_or_mod = user.role in ["admin", "moderator"]
            wants_publish  = Map.get(attrs, "is_draft") == false
            queue_enabled  = parse_bool(s["moderation_queue_enabled"], false)

            attrs =
              if queue_enabled and wants_publish and not is_admin_or_mod do
                attrs
                |> Map.put("is_draft", true)
                |> Map.put("pending_approval", true)
              else
                attrs
              end

            case Items.update_and_publish(item, attrs, tag_ids_validated) do
              {:ok, updated} ->
                # If item just got published, notify tag subscribers (async)
                if item.is_draft == true and updated.is_draft == false do
                  item_id_str_for_notif = conn.params["id"]
                  actor = user
                  Task.start(fn ->
                    {:ok, item_id_bin_notif} = Ecto.UUID.dump(item_id_str_for_notif)
                    tag_ids_for_notif =
                      Nexus.Repo.all(
                        Ecto.Query.from it in "nexus_gallery_item_tags",
                          where: it.item_id == ^item_id_bin_notif,
                          select: it.tag_id
                      )
                    subscriber_ids =
                      if tag_ids_for_notif == [] do []
                      else
                        Nexus.Repo.all(
                          Ecto.Query.from s in "nexus_gallery_subscriptions",
                            where: s.subject_type == "tag"
                              and s.subject_id in ^tag_ids_for_notif
                              and s.user_id != ^actor.id,
                            select: s.user_id
                        ) |> Enum.uniq()
                      end
                    Enum.each(subscriber_ids, fn target_id ->
                      Nexus.Notifications.notify_extension(@slug, "gallery_new_image",
                        user_id:  target_id,
                        actor_id: actor.id,
                        data:     %{"item_id" => item_id_str_for_notif}
                      )
                    end)
                  end)
                end
                json_resp(conn, 200, %{item: item_json(updated, user)})
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
              # Notify item owner of new rating (async, not self)
              Task.start(fn ->
                item_owner_id = Nexus.Repo.one(
                  Ecto.Query.from i in NexusGallery.Item,
                    where: i.id == type(^item_id_str, :binary_id),
                    select: i.user_id
                )
                if item_owner_id && item_owner_id != user.id do
                  # Only notify if no existing unread extension notification for this item
                  already_notified_rating =
                    Nexus.Repo.aggregate(
                      Ecto.Query.from(n in "notifications",
                        where: n.user_id == ^item_owner_id
                          and n.type == "extension"
                          and n.read == false
                          and fragment("(?->>'item_id') = ?", n.data, ^item_id_str)),
                      :count
                    ) > 0
                  unless already_notified_rating do
                    Nexus.Notifications.notify_extension(@slug, "gallery_rating",
                      user_id:  item_owner_id,
                      actor_id: user.id,
                      data:     %{"item_id" => item_id_str, "value" => value}
                    )
                  end
                end
              end)
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
              # Notify: item owner + all item subscribers (async)
              Task.start(fn ->
                item_owner_id = Nexus.Repo.one(
                  Ecto.Query.from i in NexusGallery.Item,
                    where: i.id == type(^item_id_str, :binary_id),
                    select: i.user_id
                )
                subscriber_ids = Nexus.Repo.all(
                  Ecto.Query.from s in "nexus_gallery_subscriptions",
                    where: s.subject_type == "item" and s.subject_id == ^id_bin
                      and s.user_id != ^user.id,
                    select: s.user_id
                )
                notify_ids =
                  ([item_owner_id] ++ subscriber_ids)
                  |> Enum.reject(&is_nil/1)
                  |> Enum.reject(&(&1 == user.id))
                  |> Enum.uniq()
                # Only notify users who have no existing unread extension notification
                # for this item — one notification per item per user.
                {:ok, item_id_bin_check} = Ecto.UUID.dump(item_id_str)
                already_notified =
                  Nexus.Repo.all(
                    Ecto.Query.from n in "notifications",
                      where: n.user_id in ^notify_ids
                        and n.type == "extension"
                        and n.read == false
                        and fragment("(?->>'item_id') = ?", n.data, ^item_id_str),
                      select: n.user_id
                  ) |> MapSet.new()
                Enum.each(notify_ids, fn target_id ->
                  unless MapSet.member?(already_notified, target_id) do
                    Nexus.Notifications.notify_extension(@slug, "gallery_comment",
                      user_id:  target_id,
                      actor_id: user.id,
                      data:     %{"item_id" => item_id_str, "body_preview" => String.slice(String.trim(body), 0, 80)}
                    )
                  end
                end)
              end)
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
  # Collections
  # -------------------------------------------------------------------------

  get "/my-collections" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      colls = Nexus.Repo.all(
        Ecto.Query.from c in NexusGallery.Collection,
          where: c.user_id == ^user.id,
          order_by: [desc: c.inserted_at]
      )
      json_resp(conn, 200, %{collections: Enum.map(colls, &collection_json/1)})
    end)
  end

  get "/collections" do
    require_permission(conn, "can_view_gallery", fn conn ->
      params   = conn.query_params
      s        = settings()
      per_page = parse_int(params["per_page"], parse_int(s["items_per_page"], 24))
      opts = [
        page:     parse_int(params["page"], 1),
        per_page: per_page,
        sort:     params["sort"] || "newest",
        user_id:  params["user_id"] && parse_int(params["user_id"], nil),
        search:   params["search"],
      ]
      {collections, total} = NexusGallery.Collections.list_collections(opts)
      per = Keyword.get(opts, :per_page)
      page = Keyword.get(opts, :page)
      json_resp(conn, 200, %{
        collections: Enum.map(collections, &collection_json/1),
        total:       total,
        page:        page,
        per_page:    per,
        total_pages: ceil(total / per)
      })
    end)
  end

  post "/collections" do
    require_permission(conn, "can_create_collection", fn conn ->
      user   = conn.assigns.current_user
      params = conn.body_params
      title  = params["title"]
      if is_nil(title) or String.trim(title) == "" do
        json_resp(conn, 422, %{error: "Title is required"})
      else
        case NexusGallery.Collections.create_collection(user.id, %{
          "title"       => String.trim(title),
          "description" => params["description"],
          "is_draft"    => false
        }) do
          {:ok, coll}         -> json_resp(conn, 201, %{collection: collection_json(coll)})
          {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
        end
      end
    end)
  end

  get "/collections/:slug" do
    require_permission(conn, "can_view_gallery", fn conn ->
      user = conn.assigns[:current_user]
      case NexusGallery.Collections.get_collection_with_items(conn.params["slug"]) do
        nil  -> json_resp(conn, 404, %{error: "Collection not found"})
        coll ->
          can_edit   = user != nil and (user.id == coll.user_id or user.role in ["admin", "moderator"])
          can_delete = can_edit
          json_resp(conn, 200, %{collection: Map.merge(coll, %{
            can_edit:   can_edit,
            can_delete: can_delete,
            items:      Enum.map(coll.items, fn i -> Map.drop(i, [:updated_at]) end)
          })})
      end
    end)
  end

  patch "/collections/:slug" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      case NexusGallery.Collections.get_collection_by_slug(conn.params["slug"]) do
        nil  -> json_resp(conn, 404, %{error: "Collection not found"})
        coll ->
          unless user.id == coll.user_id or user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            attrs = conn.body_params |> Map.take(["title", "description", "is_draft"])
            case NexusGallery.Collections.update_collection(coll, attrs) do
              {:ok, updated}      -> json_resp(conn, 200, %{collection: collection_json(updated)})
              {:error, changeset} -> json_resp(conn, 422, %{errors: format_errors(changeset)})
            end
          end
      end
    end)
  end

  delete "/collections/:slug" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      case NexusGallery.Collections.get_collection_by_slug(conn.params["slug"]) do
        nil  -> json_resp(conn, 404, %{error: "Collection not found"})
        coll ->
          unless user.id == coll.user_id or user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            case NexusGallery.Collections.delete_collection(coll) do
              :ok              -> json_resp(conn, 200, %{ok: true})
              {:error, reason} -> json_resp(conn, 500, %{error: inspect(reason)})
            end
          end
      end
    end)
  end

  post "/collections/:slug/items" do
    require_auth(conn, fn conn ->
      user    = conn.assigns.current_user
      item_id = conn.body_params["item_id"]
      if is_nil(item_id) do
        json_resp(conn, 422, %{error: "item_id is required"})
      else
        case NexusGallery.Collections.get_collection_by_slug(conn.params["slug"]) do
          nil  -> json_resp(conn, 404, %{error: "Collection not found"})
          coll ->
            unless user.id == coll.user_id or user.role in ["admin", "moderator"] do
              json_resp(conn, 403, %{error: "Access denied"})
            else
              s        = settings()
              max_size = parse_int(s["max_collection_size"], 100)
              if coll.item_count >= max_size do
                json_resp(conn, 422, %{error: "Collection is full (max #{max_size} items)"})
              else
                case NexusGallery.Collections.add_item(coll, item_id) do
                  :ok              -> json_resp(conn, 200, %{ok: true, item_count: coll.item_count + 1})
                  {:error, reason} -> json_resp(conn, 422, %{error: reason})
                end
              end
            end
        end
      end
    end)
  end

  delete "/collections/:slug/items/:item_id" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      case NexusGallery.Collections.get_collection_by_slug(conn.params["slug"]) do
        nil  -> json_resp(conn, 404, %{error: "Collection not found"})
        coll ->
          unless user.id == coll.user_id or user.role in ["admin", "moderator"] do
            json_resp(conn, 403, %{error: "Access denied"})
          else
            case NexusGallery.Collections.remove_item(coll, conn.params["item_id"]) do
              :ok              -> json_resp(conn, 200, %{ok: true, item_count: max(coll.item_count - 1, 0)})
              {:error, reason} -> json_resp(conn, 422, %{error: reason})
            end
          end
      end
    end)
  end

  # Returns the current user's collections that contain this item
  get "/items/:id/collections" do
    require_auth(conn, fn conn ->
      user = conn.assigns.current_user
      colls = NexusGallery.Collections.collections_for_item(conn.params["id"], user.id)
      json_resp(conn, 200, %{collections: Enum.map(colls, &collection_json/1)})
    end)
  end


  # -------------------------------------------------------------------------
  # User profile (gallery)
  # -------------------------------------------------------------------------

  get "/users/:username" do
    require_permission(conn, "can_view_gallery", fn conn ->
      username = conn.params["username"]
      user = Nexus.Repo.one(
        Ecto.Query.from u in "users",
          where: fragment("lower(?::text)", u.username) == ^String.downcase(username),
          select: %{
            id:         u.id,
            username:   fragment("?::text", u.username),
            avatar_url: u.avatar_url,
            bio:        u.bio
          }
      )
      case user do
        nil  -> json_resp(conn, 404, %{error: "User not found"})
        user ->
          {_items, total} = NexusGallery.Items.list_items([
            user_id: user.id, page: 1, per_page: 1
          ])
          json_resp(conn, 200, %{user: Map.put(user, :item_count, total)})
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Subscriptions
  # -------------------------------------------------------------------------

  get "/subscriptions/check" do
    require_auth(conn, fn conn ->
      user         = conn.assigns.current_user
      subject_type = conn.query_params["subject_type"]
      subject_id   = conn.query_params["subject_id"]

      if is_nil(subject_type) or is_nil(subject_id) do
        json_resp(conn, 422, %{error: "subject_type and subject_id are required"})
      else
        case Ecto.UUID.dump(subject_id) do
          {:ok, id_bin} ->
            subscribed = Nexus.Repo.aggregate(
              Ecto.Query.from(s in "nexus_gallery_subscriptions",
                where: s.user_id == ^user.id
                  and s.subject_type == ^subject_type
                  and s.subject_id == ^id_bin),
              :count, :id
            ) > 0
            json_resp(conn, 200, %{subscribed: subscribed})
          :error ->
            json_resp(conn, 200, %{subscribed: false})
        end
      end
    end)
  end

  post "/subscriptions" do
    require_permission(conn, "can_subscribe", fn conn ->
      user         = conn.assigns.current_user
      subject_type = conn.body_params["subject_type"]
      subject_id   = conn.body_params["subject_id"]

      if is_nil(subject_type) or is_nil(subject_id) do
        json_resp(conn, 422, %{error: "subject_type and subject_id are required"})
      else
        case Ecto.UUID.dump(subject_id) do
          {:ok, id_bin} ->
            already = Nexus.Repo.aggregate(
              Ecto.Query.from(s in "nexus_gallery_subscriptions",
                where: s.user_id == ^user.id
                  and s.subject_type == ^subject_type
                  and s.subject_id == ^id_bin),
              :count, :id
            ) > 0
            unless already do
              {:ok, sub_id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              Nexus.Repo.insert_all("nexus_gallery_subscriptions", [%{
                id:           sub_id_bin,
                user_id:      user.id,
                subject_type: subject_type,
                subject_id:   id_bin,
                inserted_at:  now,
                updated_at:   now
              }])
            end
            json_resp(conn, 200, %{subscribed: true})
          :error ->
            json_resp(conn, 404, %{error: "Invalid subject_id"})
        end
      end
    end)
  end

  delete "/subscriptions/:subject_type/:subject_id" do
    require_auth(conn, fn conn ->
      user         = conn.assigns.current_user
      subject_type = conn.params["subject_type"]
      subject_id   = conn.params["subject_id"]
      case Ecto.UUID.dump(subject_id) do
        {:ok, id_bin} ->
          Nexus.Repo.delete_all(
            Ecto.Query.from s in "nexus_gallery_subscriptions",
              where: s.user_id == ^user.id
                and s.subject_type == ^subject_type
                and s.subject_id == ^id_bin
          )
          json_resp(conn, 200, %{subscribed: false})
        :error ->
          json_resp(conn, 404, %{error: "Invalid subject_id"})
      end
    end)
  end


  # -------------------------------------------------------------------------
  # Following activity feed
  # -------------------------------------------------------------------------

  get "/following" do
    require_auth(conn, fn conn ->
      user    = conn.assigns.current_user
      page    = parse_int(conn.query_params["page"], 1) |> max(1)
      per     = 20
      offset  = (page - 1) * per

      # Load all subscriptions for this user
      subs = Nexus.Repo.all(
        Ecto.Query.from s in "nexus_gallery_subscriptions",
          where: s.user_id == ^user.id,
          select: %{subject_type: s.subject_type, subject_id: fragment("?::text", s.subject_id)}
      )

      item_ids   = subs |> Enum.filter(&(&1.subject_type == "item"))       |> Enum.map(&(&1.subject_id))
      coll_ids   = subs |> Enum.filter(&(&1.subject_type == "collection")) |> Enum.map(&(&1.subject_id))
      tag_ids    = subs |> Enum.filter(&(&1.subject_type == "tag"))        |> Enum.map(&(&1.subject_id))

      events = []

      # Followed items themselves — show the item as an entry
      events = events ++ if item_ids == [] do [] else
        Nexus.Repo.all(
          Ecto.Query.from i in NexusGallery.Item,
            where: fragment("?::text", i.id) in ^item_ids
              and i.is_draft == false,
            order_by: [desc: i.inserted_at],
            limit: 50,
            select: %{
              type:        "followed_item",
              subject_id:  fragment("?::text", i.id),
              item_id:     fragment("?::text", i.id),
              title:       i.title,
              file_url:    i.file_url,
              actor_id:    i.user_id,
              occurred_at: i.inserted_at
            }
        )
      end

      # New comments on followed items
      events = events ++ if item_ids == [] do [] else
        Nexus.Repo.all(
          Ecto.Query.from c in "nexus_gallery_comments",
            where: fragment("?::text", c.subject_id) in ^item_ids
              and c.subject_type == "item"
              and c.user_id != ^user.id,
            order_by: [desc: c.inserted_at],
            limit: 50,
            select: %{
              type:       "comment",
              subject_id: fragment("?::text", c.subject_id),
              item_id:    fragment("?::text", c.subject_id),
              actor_id:   c.user_id,
              body:       c.body,
              occurred_at: c.inserted_at
            }
        )
      end

      # New images on followed tags
      events = events ++ if tag_ids == [] do [] else
        Nexus.Repo.all(
          Ecto.Query.from it in "nexus_gallery_item_tags",
            join: i in NexusGallery.Item, on: i.id == it.item_id,
            where: fragment("?::text", it.tag_id) in ^tag_ids
              and i.is_draft == false
              and i.user_id != ^user.id,
            order_by: [desc: i.inserted_at],
            limit: 50,
            select: %{
              type:        "new_item",
              subject_id:  fragment("?::text", it.tag_id),
              item_id:     fragment("?::text", i.id),
              title:       i.title,
              file_url:    i.file_url,
              actor_id:    i.user_id,
              occurred_at: i.inserted_at
            }
        )
      end

      # New items added to followed collections
      events = events ++ if coll_ids == [] do [] else
        Nexus.Repo.all(
          Ecto.Query.from ci in "nexus_gallery_collection_items",
            join: i in NexusGallery.Item, on: i.id == ci.item_id,
            where: fragment("?::text", ci.collection_id) in ^coll_ids
              and i.is_draft == false
              and i.user_id != ^user.id,
            order_by: [desc: i.inserted_at],
            limit: 50,
            select: %{
              type:          "collection_item",
              subject_id:    fragment("?::text", ci.collection_id),
              item_id:       fragment("?::text", i.id),
              title:         i.title,
              file_url:      i.file_url,
              actor_id:      i.user_id,
              occurred_at:   i.inserted_at
            }
        )
      end

      # Sort all events by occurred_at desc, then paginate
      all_sorted = Enum.sort_by(events, & &1.occurred_at, {:desc, NaiveDateTime})
      total      = length(all_sorted)
      sorted     = all_sorted |> Enum.drop(offset) |> Enum.take(per)

      # Batch-load actor user info
      actor_ids = sorted |> Enum.map(& &1.actor_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      actors = if actor_ids == [] do %{} else
        Nexus.Repo.all(
          Ecto.Query.from u in "users",
            where: u.id in ^actor_ids,
            select: %{id: u.id, username: fragment("?::text", u.username), avatar_url: u.avatar_url}
        ) |> Map.new(&{&1.id, &1})
      end

      enriched = Enum.map(sorted, fn e ->
        Map.put(e, :actor, Map.get(actors, e.actor_id))
      end)

      json_resp(conn, 200, %{
        events:      enriched,
        total:       total,
        page:        page,
        total_pages: ceil(max(total, 1) / per)
      })
    end)
  end



  # -------------------------------------------------------------------------
  # Extension settings (admin only — save harvest_enabled etc.)
  # -------------------------------------------------------------------------

  patch "/settings" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      params   = conn.body_params
      allowed  = ~w(harvest_enabled)
      updates  = Map.take(params, allowed)
      if map_size(updates) == 0 do
        json_resp(conn, 422, %{error: "No valid settings keys provided"})
      else
        ext = Nexus.Extensions.get_extension_by_slug(@slug)
        case Nexus.Extensions.update_extension_settings(ext, updates) do
          {:ok, _}         -> json_resp(conn, 200, %{ok: true})
          {:error, reason} -> json_resp(conn, 500, %{error: inspect(reason)})
        end
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Harvest mappings
  # -------------------------------------------------------------------------

  get "/harvest-mappings" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      mappings = Nexus.Repo.all(
        Ecto.Query.from m in "nexus_gallery_harvest_mappings",
          order_by: [asc: m.inserted_at],
          select: %{
            id:             fragment("?::text", m.id),
            forum_tag_slug: m.forum_tag_slug,
            gallery_tag_id: fragment("?::text", m.gallery_tag_id)
          }
      )
      # Enrich with gallery tag names
      gallery_tag_ids = Enum.map(mappings, & &1.gallery_tag_id) |> Enum.uniq()
      tags_by_id =
        if gallery_tag_ids == [] do %{} else
          Nexus.Repo.all(
            Ecto.Query.from t in NexusGallery.Tag,
              where: fragment("?::text", t.id) in ^gallery_tag_ids,
              select: %{id: fragment("?::text", t.id), name: t.name, color: t.color, slug: t.slug}
          ) |> Map.new(&{&1.id, &1})
        end
      enriched = Enum.map(mappings, fn m ->
        Map.put(m, :gallery_tag, Map.get(tags_by_id, m.gallery_tag_id))
      end)
      json_resp(conn, 200, %{mappings: enriched})
    end)
  end

  post "/harvest-mappings" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      forum_tag_slug = conn.body_params["forum_tag_slug"]
      gallery_tag_id = conn.body_params["gallery_tag_id"]

      cond do
        is_nil(forum_tag_slug) or String.trim(forum_tag_slug) == "" ->
          json_resp(conn, 422, %{error: "forum_tag_slug is required"})
        is_nil(gallery_tag_id) ->
          json_resp(conn, 422, %{error: "gallery_tag_id is required"})
        true ->
          forum_slug = String.trim(forum_tag_slug)
          case Ecto.UUID.dump(gallery_tag_id) do
            {:ok, gallery_tag_bin} ->
              # Check for duplicate forum_tag_slug
              existing = Nexus.Repo.aggregate(
                Ecto.Query.from(m in "nexus_gallery_harvest_mappings",
                  where: m.forum_tag_slug == ^forum_slug),
                :count
              )
              if existing > 0 do
                json_resp(conn, 422, %{error: "A mapping for that forum tag already exists"})
              else
                {:ok, id_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
                now = DateTime.utc_now() |> DateTime.truncate(:second)
                Nexus.Repo.insert_all("nexus_gallery_harvest_mappings", [%{
                  id:             id_bin,
                  forum_tag_slug: forum_slug,
                  gallery_tag_id: gallery_tag_bin,
                  inserted_at:    now,
                  updated_at:     now
                }])
                json_resp(conn, 201, %{ok: true})
              end
            :error ->
              json_resp(conn, 422, %{error: "Invalid gallery_tag_id"})
          end
      end
    end)
  end

  delete "/harvest-mappings/:id" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      mapping_id = conn.params["id"]
      case Ecto.UUID.dump(mapping_id) do
        {:ok, id_bin} ->
          Nexus.Repo.delete_all(
            Ecto.Query.from m in "nexus_gallery_harvest_mappings",
              where: m.id == ^id_bin
          )
          json_resp(conn, 200, %{ok: true})
        :error ->
          json_resp(conn, 404, %{error: "Not found"})
      end
    end)
  end


  # -------------------------------------------------------------------------
  # Moderation queue
  # -------------------------------------------------------------------------

  get "/queue" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      params   = conn.query_params
      page     = parse_int(params["page"], 1) |> max(1)
      per      = 20
      offset   = (page - 1) * per

      {items, total} = NexusGallery.Items.list_items([
        page:     page,
        per_page: per,
        queue:    true
      ])

      json_resp(conn, 200, %{
        items:       Enum.map(items, &item_json(&1, nil)),
        total:       total,
        page:        page,
        total_pages: ceil(max(total, 1) / per)
      })
    end)
  end

  post "/queue/:id/approve" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      item_id = conn.params["id"]
      case NexusGallery.Items.get_item(item_id) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless item.pending_approval do
            json_resp(conn, 422, %{error: "Item is not pending approval"})
          else
            case NexusGallery.Items.update_and_publish(item, %{"is_draft" => false, "pending_approval" => false}, nil) do
              {:ok, updated} -> json_resp(conn, 200, %{item: item_json(updated, nil)})
              {:error, cs}   -> json_resp(conn, 422, %{errors: format_errors(cs)})
            end
          end
      end
    end)
  end

  post "/queue/:id/reject" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      item_id = conn.params["id"]
      case NexusGallery.Items.get_item(item_id) do
        nil  -> json_resp(conn, 404, %{error: "Item not found"})
        item ->
          unless item.pending_approval do
            json_resp(conn, 422, %{error: "Item is not pending approval"})
          else
            NexusGallery.Items.delete_item(item)
            json_resp(conn, 200, %{ok: true})
          end
      end
    end)
  end


  # -------------------------------------------------------------------------
  # Admin stats
  # -------------------------------------------------------------------------

  get "/admin-stats" do
    require_permission(conn, "can_manage_gallery", fn conn ->
      import Ecto.Query

      # Totals
      total_images   = Nexus.Repo.aggregate(from(i in NexusGallery.Item, where: i.media_type == "image"  and i.is_draft == false and i.pending_approval == false), :count)
      total_videos   = Nexus.Repo.aggregate(from(i in NexusGallery.Item, where: i.media_type == "video"  and i.is_draft == false and i.pending_approval == false), :count)
      total_embeds   = Nexus.Repo.aggregate(from(i in NexusGallery.Item, where: i.media_type == "embed"  and i.is_draft == false and i.pending_approval == false), :count)
      total_drafts   = Nexus.Repo.aggregate(from(i in NexusGallery.Item, where: i.is_draft == true and i.pending_approval == false), :count)
      total_pending  = Nexus.Repo.aggregate(from(i in NexusGallery.Item, where: i.pending_approval == true), :count)
      total_comments = Nexus.Repo.aggregate(from(c in "nexus_gallery_comments"), :count)
      total_ratings  = Nexus.Repo.aggregate(from(r in "nexus_gallery_ratings"), :count)
      total_reactions = Nexus.Repo.aggregate(from(r in "nexus_gallery_reactions"), :count)
      total_collections = Nexus.Repo.aggregate(from(c in NexusGallery.Collection), :count)

      # Uploads over last 30 days grouped by day
      thirty_ago = DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)
      daily_uploads = Nexus.Repo.all(
        from i in NexusGallery.Item,
          where: i.is_draft == false
            and i.pending_approval == false
            and i.inserted_at >= ^thirty_ago,
          group_by: fragment("date_trunc('day', ?)", i.inserted_at),
          order_by: fragment("date_trunc('day', ?)", i.inserted_at),
          select: %{
            day:   fragment("date_trunc('day', ?)", i.inserted_at),
            count: count(i.id)
          }
      )

      # Most viewed items (top 5)
      most_viewed = Nexus.Repo.all(
        from i in NexusGallery.Item,
          where: i.is_draft == false and i.pending_approval == false,
          order_by: [desc: i.view_count],
          limit: 5
      ) |> NexusGallery.Items.enrich_list_public()
        |> Enum.map(&widget_item_json/1)

      # Most commented items (top 5)
      comment_counts = Nexus.Repo.all(
        from c in "nexus_gallery_comments",
          where: c.subject_type == "item",
          group_by: c.subject_id,
          order_by: [desc: count(c.id)],
          limit: 5,
          select: {fragment("?::text", c.subject_id), count(c.id)}
      )
      most_commented =
        if comment_counts == [] do []
        else
          ids = Enum.map(comment_counts, fn {id, _} -> id end)
          count_map = Map.new(comment_counts)
          Nexus.Repo.all(
            from i in NexusGallery.Item,
              where: fragment("?::text", i.id) in ^ids
                and i.is_draft == false
                and i.pending_approval == false
          )
          |> NexusGallery.Items.enrich_list_public()
          |> Enum.sort_by(fn i -> Map.get(count_map, i.id, 0) end, :desc)
          |> Enum.map(fn i ->
            Map.put(widget_item_json(i), :comment_count, Map.get(count_map, i.id, 0))
          end)
        end

      json_resp(conn, 200, %{
        totals: %{
          images:      total_images,
          videos:      total_videos,
          embeds:      total_embeds,
          drafts:      total_drafts,
          pending:     total_pending,
          comments:    total_comments,
          ratings:     total_ratings,
          reactions:   total_reactions,
          collections: total_collections
        },
        daily_uploads:  Enum.map(daily_uploads, fn d ->
          %{day: d.day, count: d.count}
        end),
        most_viewed:    most_viewed,
        most_commented: most_commented
      })
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

  defp collection_json(c) do
    %{
      id:          Map.get(c, :id) || uuid_str(Map.get(c, :id)),
      user_id:     c.user_id,
      user:        Map.get(c, :user),
      title:       c.title,
      slug:        c.slug,
      description: c.description,
      cover_url:   c.cover_url,
      is_draft:    c.is_draft,
      is_featured: c.is_featured,
      item_count:  c.item_count,
      inserted_at: c.inserted_at
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
