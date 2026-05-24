(function () {
  "use strict";

  const NE   = window.NexusExtensions;
  const SLUG = "nexus-gallery";
  const { useState, useEffect, useRef, useCallback } = window.React;
  const { Toggle, toast } = window.NexusComponents;

  // ─── Shared fetch helper ─────────────────────────────────────────────────
  // All calls to /ext/nexus-gallery/api/... must include the Bearer token.
  // window.api is for Nexus core /api/v1/... only — guide §9.11.

  function authHeaders() {
    const token = localStorage.getItem("nexus_token");
    return token
      ? { "authorization": "Bearer " + token, "content-type": "application/json" }
      : { "content-type": "application/json" };
  }

  function apiGet(path) {
    return fetch("/ext/" + SLUG + "/api" + path, { headers: authHeaders() })
      .then(function (r) { return r.json(); });
  }

  function apiPost(path, body) {
    return fetch("/ext/" + SLUG + "/api" + path, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify(body),
    }).then(function (r) { return r.json(); });
  }

  function apiPatch(path, body) {
    return fetch("/ext/" + SLUG + "/api" + path, {
      method: "PATCH",
      headers: authHeaders(),
      body: JSON.stringify(body),
    }).then(function (r) { return r.json(); });
  }

  function apiDelete(path) {
    return fetch("/ext/" + SLUG + "/api" + path, {
      method: "DELETE",
      headers: authHeaders(),
    }).then(function (r) { return r.json(); });
  }

  // ─── Tags tab ────────────────────────────────────────────────────────────

  // Inline form for creating or editing a tag.
  function TagForm({ initial, onSave, onCancel }) {
    var defaults = initial || { name: "", color: "#7c5cfc", allow_images: true, allow_videos: true, allow_embeds: true };
    var _s = useState(defaults);
    var form = _s[0]; var setForm = _s[1];
    var _saving = useState(false);
    var saving = _saving[0]; var setSaving = _saving[1];

    function handleSubmit() {
      if (!form.name.trim()) {
        toast("Name is required", "err");
        return;
      }
      setSaving(true);
      onSave(form).finally(function () { setSaving(false); });
    }

    var sectionStyle = { fontSize: 12, color: "var(--t4)", fontWeight: 500, marginBottom: 6 };
    var inputStyle = {
      width: "100%", padding: "8px 12px",
      background: "rgba(255,255,255,0.05)", border: "0.5px solid var(--b2)",
      borderRadius: 10, color: "var(--t1)", fontSize: 14,
      outline: "none", fontFamily: "inherit",
    };
    var mediaToggleStyle = { display: "flex", alignItems: "center", gap: 10, padding: "6px 0" };

    return React.createElement("div", {
      style: {
        background: "var(--s2)", border: "0.5px solid var(--b2)",
        borderRadius: 12, padding: "16px 18px", marginBottom: 10,
      }
    },
      // Name
      React.createElement("div", { style: { marginBottom: 14 } },
        React.createElement("div", { style: sectionStyle }, "Name"),
        React.createElement("input", {
          style: inputStyle,
          value: form.name,
          placeholder: "Tag name",
          onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { name: e.target.value }); }); },
          autoFocus: true,
        })
      ),
      // Color
      React.createElement("div", { style: { marginBottom: 14 } },
        React.createElement("div", { style: sectionStyle }, "Color"),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10 } },
          React.createElement("input", {
            style: Object.assign({}, inputStyle, { maxWidth: 130 }),
            value: form.color,
            placeholder: "#7c5cfc",
            onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); },
          }),
          React.createElement("input", {
            type: "color",
            value: form.color || "#7c5cfc",
            onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); },
            style: { width: 36, height: 36, border: "none", borderRadius: 6, cursor: "pointer", background: "none" },
          }),
          React.createElement("div", {
            style: {
              width: 28, height: 28, borderRadius: "50%",
              background: form.color || "#7c5cfc",
              flexShrink: 0,
            }
          })
        )
      ),
      // Media type allowlist
      React.createElement("div", { style: { marginBottom: 16 } },
        React.createElement("div", { style: sectionStyle }, "Allowed media types"),
        React.createElement("div", { style: mediaToggleStyle },
          React.createElement(Toggle, {
            value: form.allow_images,
            onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_images: v }); }); },
            label: "Images",
          })
        ),
        React.createElement("div", { style: mediaToggleStyle },
          React.createElement(Toggle, {
            value: form.allow_videos,
            onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_videos: v }); }); },
            label: "Videos",
          })
        ),
        React.createElement("div", { style: mediaToggleStyle },
          React.createElement(Toggle, {
            value: form.allow_embeds,
            onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_embeds: v }); }); },
            label: "Embeds",
          })
        )
      ),
      // Actions
      React.createElement("div", { style: { display: "flex", gap: 8 } },
        React.createElement("button", {
          className: "btn-primary",
          style: { fontSize: 13, padding: "7px 16px" },
          onClick: handleSubmit,
          disabled: saving,
        }, saving ? "Saving…" : (initial ? "Save changes" : "Create tag")),
        React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 13, padding: "7px 16px" },
          onClick: onCancel,
          disabled: saving,
        }, "Cancel")
      )
    );
  }

  // A single row in the tag list.
  function TagRow({ tag, onEdit, onDelete, dragHandleProps }) {
    var badgeStyle = function (color, active) {
      return {
        fontSize: 10, padding: "1px 6px", borderRadius: 4,
        fontWeight: 500,
        background: active ? color + "22" : "rgba(255,255,255,0.04)",
        color: active ? color : "var(--t5)",
        border: "0.5px solid " + (active ? color + "44" : "var(--b1)"),
      };
    };

    return React.createElement("div", {
      style: {
        display: "flex", alignItems: "center", gap: 10,
        padding: "10px 0", borderBottom: "0.5px solid var(--b1)",
      }
    },
      // Drag handle
      React.createElement("div", Object.assign({
        style: { color: "var(--t5)", cursor: "grab", fontSize: 13, flexShrink: 0 },
      }, dragHandleProps),
        React.createElement("i", { className: "fa-solid fa-grip-vertical" })
      ),
      // Color dot
      React.createElement("div", {
        style: { width: 10, height: 10, borderRadius: "50%", background: tag.color, flexShrink: 0 }
      }),
      // Name
      React.createElement("span", {
        style: { fontSize: 13, color: "var(--t2)", fontWeight: 500, flex: 1, minWidth: 0,
                 overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }
      }, tag.name),
      // Media badges
      React.createElement("div", { style: { display: "flex", gap: 4 } },
        React.createElement("span", { style: badgeStyle("#60a5fa", tag.allow_images) }, "IMG"),
        React.createElement("span", { style: badgeStyle("#fbbf24", tag.allow_videos) }, "VID"),
        React.createElement("span", { style: badgeStyle("#a78bfa", tag.allow_embeds) }, "EMB")
      ),
      // Count
      React.createElement("span", {
        style: { fontSize: 11.5, color: "var(--t5)", minWidth: 28, textAlign: "right", flexShrink: 0 }
      }, tag.item_count),
      // Edit
      React.createElement("button", {
        onClick: function () { onEdit(tag); },
        style: {
          fontSize: 11.5, padding: "3px 9px", borderRadius: 8,
          border: "0.5px solid var(--b2)", color: "var(--t4)",
          background: "transparent", cursor: "pointer", fontFamily: "inherit",
        }
      }, React.createElement("i", { className: "fa-solid fa-pen" })),
      // Delete
      React.createElement("button", {
        onClick: function () { onDelete(tag); },
        style: {
          fontSize: 11.5, padding: "3px 9px", borderRadius: 8,
          border: "0.5px solid rgba(248,113,113,0.3)", color: "var(--red)",
          background: "transparent", cursor: "pointer", fontFamily: "inherit",
        }
      }, React.createElement("i", { className: "fa-solid fa-trash" }))
    );
  }

  // Tags tab — full CRUD with drag-to-reorder.
  // Drag is implemented with the HTML5 drag-and-drop API. No external library.
  function TagsTab() {
    var _tags = useState(null);
    var tags = _tags[0]; var setTags = _tags[1];
    var _loading = useState(true);
    var loading = _loading[0]; var setLoading = _loading[1];
    var _creating = useState(false);
    var creating = _creating[0]; var setCreating = _creating[1];
    var _editing = useState(null);
    var editing = _editing[0]; var setEditing = _editing[1];
    var dragIndex = useRef(null);
    var dragOverIndex = useRef(null);

    function load() {
      setLoading(true);
      apiGet("/tags").then(function (d) {
        setTags(d.tags || []);
        setLoading(false);
      }).catch(function () {
        toast("Failed to load tags", "err");
        setLoading(false);
      });
    }

    useEffect(load, []);

    function handleCreate(form) {
      return apiPost("/tags", form).then(function (d) {
        if (d.tag) {
          setTags(function (prev) { return prev.concat(d.tag); });
          setCreating(false);
          toast("Tag created");
        } else {
          toast((d.errors ? JSON.stringify(d.errors) : d.error) || "Failed to create tag", "err");
        }
      });
    }

    function handleEdit(form) {
      return apiPatch("/tags/" + editing.id, form).then(function (d) {
        if (d.tag) {
          setTags(function (prev) { return prev.map(function (t) { return t.id === d.tag.id ? d.tag : t; }); });
          setEditing(null);
          toast("Tag updated");
        } else {
          toast((d.errors ? JSON.stringify(d.errors) : d.error) || "Failed to update tag", "err");
        }
      });
    }

    function handleDelete(tag) {
      if (!window.confirm("Delete tag \"" + tag.name + "\"? This cannot be undone.")) return;
      apiDelete("/tags/" + tag.id).then(function (d) {
        if (d.ok) {
          setTags(function (prev) { return prev.filter(function (t) { return t.id !== tag.id; }); });
          toast("Tag deleted");
        } else {
          toast(d.error || "Failed to delete tag", "err");
        }
      });
    }

    // HTML5 drag-and-drop reorder
    function handleDragStart(index) {
      dragIndex.current = index;
    }

    function handleDragOver(e, index) {
      e.preventDefault();
      dragOverIndex.current = index;
    }

    function handleDrop() {
      var from = dragIndex.current;
      var to = dragOverIndex.current;
      if (from === null || to === null || from === to) return;

      var reordered = tags.slice();
      var moved = reordered.splice(from, 1)[0];
      reordered.splice(to, 0, moved);
      setTags(reordered);
      dragIndex.current = null;
      dragOverIndex.current = null;

      apiPost("/tags/reorder", { ids: reordered.map(function (t) { return t.id; }) })
        .then(function (d) {
          if (!d.ok) toast("Failed to save order", "err");
        })
        .catch(function () { toast("Failed to save order", "err"); });
    }

    if (loading) {
      return React.createElement("div", {
        style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" }
      }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }));
    }

    return React.createElement("div", null,
      // Header row
      React.createElement("div", {
        style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 }
      },
        React.createElement("div", { style: { fontSize: 13, color: "var(--t4)" } },
          tags ? tags.length + " tag" + (tags.length === 1 ? "" : "s") + " · drag to reorder" : ""
        ),
        !creating && React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 12.5, display: "flex", alignItems: "center", gap: 6 },
          onClick: function () { setCreating(true); setEditing(null); },
        },
          React.createElement("i", { className: "fa-solid fa-plus" }),
          " New tag"
        )
      ),
      // Create form
      creating && React.createElement(TagForm, {
        onSave: handleCreate,
        onCancel: function () { setCreating(false); },
      }),
      // Tag list
      tags && tags.length === 0 && !creating && React.createElement("div", {
        style: { padding: "32px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 }
      }, "No tags yet. Create one to get started."),
      tags && tags.map(function (tag, index) {
        if (editing && editing.id === tag.id) {
          return React.createElement(TagForm, {
            key: tag.id,
            initial: tag,
            onSave: handleEdit,
            onCancel: function () { setEditing(null); },
          });
        }
        return React.createElement("div", {
          key: tag.id,
          draggable: true,
          onDragStart: function () { handleDragStart(index); },
          onDragOver: function (e) { handleDragOver(e, index); },
          onDrop: handleDrop,
        },
          React.createElement(TagRow, {
            tag: tag,
            onEdit: function (t) { setEditing(t); setCreating(false); },
            onDelete: handleDelete,
            dragHandleProps: {},
          })
        );
      })
    );
  }

  // ─── Placeholder for tabs not yet built ──────────────────────────────────

  function ComingSoonTab({ label }) {
    return React.createElement("div", {
      style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 }
    },
      React.createElement("i", {
        className: "fa-solid fa-clock",
        style: { fontSize: 28, display: "block", marginBottom: 12, color: "var(--t5)" }
      }),
      label + " coming in a future phase."
    );
  }

  // ─── Admin panel ─────────────────────────────────────────────────────────

  function GalleryAdminPanel() {
    var _ref = window.NexusExtensionTemplates;
    var SimpleSettingsPanel = _ref.SimpleSettingsPanel;
    var TabbedPanel = _ref.TabbedPanel;

    return React.createElement(TabbedPanel, {
      tabs: [
        {
          key:   "general",
          label: "General",
          icon:  "fa-gear",
          render: function () {
            return React.createElement(SimpleSettingsPanel, {
              slug: SLUG,
              fields: [
                // Core toggles
                { key: "gallery_enabled",          label: "Gallery enabled",        type: "boolean",
                  hint: "Show Gallery in the Explore sidebar and make all routes accessible." },
                { key: "ratings_enabled",           label: "Ratings enabled",        type: "boolean",
                  hint: "Allow members to give 1–5 star ratings on images, videos, and collections." },
                { key: "comments_enabled",          label: "Comments enabled",       type: "boolean",
                  hint: "Allow members to comment on gallery items and collections." },
                { key: "reactions_enabled",         label: "Reactions enabled",      type: "boolean",
                  hint: "Allow members to react to gallery items and collections with emoji." },
                // Moderation
                { key: "moderation_queue_enabled",  label: "Moderation queue",       type: "boolean",
                  hint: "New uploads go into a pending queue and require admin approval before appearing publicly." },
                // Limits
                { key: "max_tags_per_item",         label: "Max tags per item",      type: "number",
                  hint: "Maximum number of tags a member can apply to a single image, video, or embed." },
                { key: "max_collection_size",       label: "Max collection size",    type: "number",
                  hint: "Maximum number of items a collection can contain." },
                { key: "items_per_page",            label: "Items per page",         type: "select",
                  options: [
                    { value: "24", label: "24" },
                    { value: "36", label: "36" },
                    { value: "48", label: "48" },
                    { value: "60", label: "60" },
                  ]
                },
                // Video
                { key: "videos_enabled",            label: "Video uploads enabled",  type: "boolean",
                  hint: "Allow members to upload video files (MP4, WebM). Disabled by default — requires sufficient storage." },
                { key: "max_video_size_mb",         label: "Max video size (MB)",    type: "number",
                  hint: "Per-file size cap for video uploads. Nexus's global upload limit also applies." },
              ],
            });
          },
        },
        {
          key:   "tags",
          label: "Tags",
          icon:  "fa-tag",
          render: function () { return React.createElement(TagsTab); },
        },
        {
          key:   "queue",
          label: "Queue",
          icon:  "fa-clock",
          render: function () { return React.createElement(ComingSoonTab, { label: "Moderation queue" }); },
        },
        {
          key:   "harvest",
          label: "Harvest",
          icon:  "fa-seedling",
          render: function () { return React.createElement(ComingSoonTab, { label: "Image harvest configuration" }); },
        },
        {
          key:   "stats",
          label: "Stats",
          icon:  "fa-chart-bar",
          render: function () { return React.createElement(ComingSoonTab, { label: "Gallery stats" }); },
        },
      ],
    });
  }

  // ─── Route placeholders ───────────────────────────────────────────────────

  function Placeholder(props) {
    return React.createElement(
      "div",
      { style: { padding: "48px 0", textAlign: "center", color: "var(--t4)", fontSize: 14 } },
      React.createElement("i", {
        className: "fa-solid fa-images",
        style: { fontSize: 32, display: "block", marginBottom: 16, color: "var(--t5)" },
      }),
      React.createElement("div", { style: { fontWeight: 500, color: "var(--t2)", marginBottom: 8 } }, props.title || "Gallery"),
      React.createElement("div", null, "Coming in a future phase.")
    );
  }

  function GalleryPage()        { return React.createElement(Placeholder, { title: "Gallery" }); }
  function GalleryItemPage()    { return React.createElement(Placeholder, { title: "Gallery item" }); }
  function CollectionPage()     { return React.createElement(Placeholder, { title: "Collection" }); }
  function GalleryTagPage()     { return React.createElement(Placeholder, { title: "Gallery tag" }); }
  function GalleryUserPage()    { return React.createElement(Placeholder, { title: "Gallery uploads" }); }
  function NewGalleryItemPage() { return React.createElement(Placeholder, { title: "New gallery item" }); }

  // ─── Right widget placeholders ────────────────────────────────────────────

  function GalleryStatsWidget() {
    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Gallery"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Stats coming soon.")
    );
  }

  function GalleryTopRatedWidget() {
    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top rated"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  function GalleryTagsWidget() {
    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Tags"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  function GalleryTopUploadersWidget() {
    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top uploaders"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  // ─── Profile tab placeholder ─────────────────────────────────────────────

  function GalleryProfileTab(props) {
    return React.createElement(Placeholder, { title: "Gallery uploads for " + (props.username || "") });
  }

  // ─── Register all surfaces ────────────────────────────────────────────────

  NE.registerRoute(SLUG, "/",                 GalleryPage,        { title: "Gallery" });
  NE.registerRoute(SLUG, "/:uuid",            GalleryItemPage,    { title: "Gallery item" });
  NE.registerRoute(SLUG, "/collection/:slug", CollectionPage,     { title: "Collection" });
  NE.registerRoute(SLUG, "/tag/:slug",        GalleryTagPage,     { title: "Gallery tag" });
  NE.registerRoute(SLUG, "/user/:username",   GalleryUserPage,    { title: "Gallery uploads" });
  NE.registerRoute(SLUG, "/new/:uuid",        NewGalleryItemPage, { title: "New gallery item" });

  NE.registerAdminPanel(SLUG, {
    label:     "Gallery",
    icon:      "fa-images",
    component: GalleryAdminPanel,
  });

  NE.registerExploreItem({
    slug:     SLUG,
    path:     "/",
    label:    "Gallery",
    icon:     "fa-images",
    authOnly: false,
    priority: 50,
  });

  NE.registerRightWidget({ slug: SLUG, id: "gallery-stats",         label: "Gallery stats",         component: GalleryStatsWidget,         scope: "extension", priority: 10 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-top-rated",     label: "Gallery top rated",     component: GalleryTopRatedWidget,      scope: "extension", priority: 20 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-tags",          label: "Gallery tags",          component: GalleryTagsWidget,          scope: "extension", priority: 30 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-top-uploaders", label: "Gallery top uploaders", component: GalleryTopUploadersWidget,  scope: "extension", priority: 40 });

  NE.registerProfileTab({ slug: SLUG, id: "gallery-uploads", component: GalleryProfileTab });

  NE.registerNotificationType("gallery_comment", {
    icon: "fa-comment", iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(React.Fragment, null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",   { style: { color: "var(--t3)" } }, " commented on your gallery item.")
      );
    },
    onClick: function () {},
  });

  NE.registerNotificationType("gallery_rating", {
    icon: "fa-star", iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(React.Fragment, null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",   { style: { color: "var(--t3)" } }, " rated your gallery item.")
      );
    },
    onClick: function () {},
  });

  NE.registerNotificationType("gallery_new_image", {
    icon: "fa-images", iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(React.Fragment, null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",   { style: { color: "var(--t3)" } }, " added a new image to a tag you follow.")
      );
    },
    onClick: function () {},
  });

})();
