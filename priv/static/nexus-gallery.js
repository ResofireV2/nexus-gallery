(function () {
  "use strict";

  const NE   = window.NexusExtensions;
  const SLUG = "nexus-gallery";
  const { useState, useEffect, useRef, useCallback } = window.React;
  const { Toggle, toast } = window.NexusComponents;

  // ─── Shared fetch helpers ─────────────────────────────────────────────────
  // All calls to /ext/nexus-gallery/api/... require the Bearer token.
  // window.api is Nexus core only (hardcoded /api/v1 prefix) — guide §9.11.

  function authHeaders() {
    var token = localStorage.getItem("nexus_token");
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

  // ─── Upload a file via XHR (for progress events) ─────────────────────────
  // fetch() does not expose upload progress. XHR does via xhr.upload.onprogress.
  // The upload endpoint is /api/v1/uploads/ext/:slug — this is the Nexus core
  // upload endpoint, not our own API route.

  function uploadFileXhr(file, recordId, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr    = new XMLHttpRequest();
      var body   = new FormData();
      body.append("file", file);
      body.append("type", "extension_image");
      if (recordId) body.append("record_id", recordId);

      xhr.upload.onprogress = function (e) {
        if (e.lengthComputable) {
          onProgress(Math.round((e.loaded / e.total) * 100));
        }
      };

      xhr.onload = function () {
        try {
          var r = JSON.parse(xhr.responseText);
          if (r.url) {
            resolve(r);
          } else {
            reject(new Error(r.error || "Upload failed"));
          }
        } catch (err) {
          reject(new Error("Invalid response from upload endpoint"));
        }
      };

      xhr.onerror = function () { reject(new Error("Network error during upload")); };

      var token = localStorage.getItem("nexus_token");
      xhr.open("POST", "/api/v1/uploads/ext/" + SLUG);
      if (token) xhr.setRequestHeader("authorization", "Bearer " + token);
      // Do NOT set Content-Type manually — browser sets it with the multipart
      // boundary when the body is FormData. Guide §9.15 warns about this.
      xhr.send(body);
    });
  }

  // ─── Upload modal ─────────────────────────────────────────────────────────
  // Flarum color-reveal technique: two stacked images on the same src.
  // Bottom layer: grayscale filter, always visible.
  // Top layer: no filter, clip-path: inset((100-progress)% 0 0 0).
  // As progress increases the clip shrinks from top, revealing color bottom-up.

  function UploadModal({ onClose, onUploaded }) {
    var _entries = useState([]);
    var entries = _entries[0]; var setEntries = _entries[1];
    var inputRef = useRef(null);

    function handleFiles(files) {
      var newEntries = Array.from(files).map(function (f) {
        return {
          file:       f,
          previewUrl: URL.createObjectURL(f),
          status:     "pending",   // pending | uploading | done | error
          progress:   0,
          url:        null,
          originalUrl: null,
          uploadId:   null,
          error:      null,
          draftId:    null,
        };
      });
      setEntries(function (prev) { return prev.concat(newEntries); });
      newEntries.forEach(function (entry, i) {
        startUpload(i + entries.length, entry);
      });
    }

    function startUpload(idx, entry) {
      // Step 1: create a draft item to get a record_id
      apiPost("/items/draft", { media_type: "image" })
        .then(function (d) {
          if (!d.id) throw new Error(d.error || "Failed to create draft");
          var draftId = d.id;
          setEntries(function (prev) {
            var updated = prev.slice();
            updated[idx] = Object.assign({}, updated[idx], { status: "uploading", draftId: draftId });
            return updated;
          });
          // Step 2: upload the file with the record_id
          return uploadFileXhr(entry.file, draftId, function (progress) {
            setEntries(function (prev) {
              var updated = prev.slice();
              updated[idx] = Object.assign({}, updated[idx], { progress: progress });
              return updated;
            });
          });
        })
        .then(function (r) {
          setEntries(function (prev) {
            var updated = prev.slice();
            updated[idx] = Object.assign({}, updated[idx], {
              status:      "done",
              progress:    100,
              url:         r.url,
              originalUrl: r.original_url,
              uploadId:    r.upload && r.upload.id,
            });
            return updated;
          });
        })
        .catch(function (err) {
          setEntries(function (prev) {
            var updated = prev.slice();
            updated[idx] = Object.assign({}, updated[idx], {
              status:   "error",
              progress: 0,
              error:    err.message,
            });
            return updated;
          });
          toast(err.message || "Upload failed", "err");
        });
    }

    function handleDrop(e) {
      e.preventDefault();
      if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files);
    }

    function handleDragOver(e) { e.preventDefault(); }

    var allDone    = entries.length > 0 && entries.every(function (e) { return e.status === "done"; });
    var anyUploading = entries.some(function (e) { return e.status === "uploading" || e.status === "pending"; });

    function handleContinue() {
      var done = entries.filter(function (e) { return e.status === "done" && e.draftId; });
      if (done.length === 0) return;
      // Navigate to metadata form for the first uploaded item
      // Multiple items: first one gets the metadata form; rest are navigated to individually
      onClose();
      window.NexusExtensions.navigate("/ext/" + SLUG + "/new/" + done[0].draftId);
    }

    var overlayStyle = {
      position: "fixed", inset: 0,
      background: "rgba(0,0,0,0.6)",
      display: "flex", alignItems: "center", justifyContent: "center",
      zIndex: 9000,
    };
    var modalStyle = {
      background: "var(--s2)", border: "0.5px solid var(--b2)",
      borderRadius: 14, padding: 24,
      width: 540, maxWidth: "calc(100vw - 32px)",
      maxHeight: "80vh", overflow: "hidden",
      display: "flex", flexDirection: "column", gap: 16,
    };
    var dropZoneStyle = {
      border: "1.5px dashed var(--b2)", borderRadius: 10,
      padding: "32px 24px", textAlign: "center",
      cursor: "pointer", color: "var(--t4)", fontSize: 13,
    };
    var thumbGridStyle = {
      display: "grid",
      gridTemplateColumns: "repeat(4, 1fr)",
      gap: 8,
      overflowY: "auto",
      maxHeight: 260,
    };

    return React.createElement("div", { style: overlayStyle, onClick: function (e) { if (e.target === e.currentTarget && !anyUploading) onClose(); } },
      React.createElement("div", { style: modalStyle },
        // Header
        React.createElement("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between" } },
          React.createElement("span", { style: { fontSize: 15, fontWeight: 500, color: "var(--t1)" } }, "Upload images"),
          React.createElement("button", {
            onClick: onClose,
            disabled: anyUploading,
            style: { background: "none", border: "none", color: "var(--t4)", cursor: "pointer", fontSize: 18 },
          }, React.createElement("i", { className: "fa-solid fa-xmark" }))
        ),

        // Drop zone (shown when no files selected yet)
        entries.length === 0 && React.createElement("div", {
          style: dropZoneStyle,
          onClick: function () { inputRef.current && inputRef.current.click(); },
          onDrop: handleDrop,
          onDragOver: handleDragOver,
        },
          React.createElement("i", { className: "fa-solid fa-upload", style: { fontSize: 28, display: "block", marginBottom: 10, color: "var(--t5)" } }),
          React.createElement("div", null, "Click to select images or drag and drop"),
          React.createElement("div", { style: { fontSize: 11, color: "var(--t5)", marginTop: 4 } }, "JPEG, PNG, GIF, WebP")
        ),

        // Thumbnail grid with color-reveal progress
        entries.length > 0 && React.createElement("div", { style: thumbGridStyle },
          entries.map(function (entry, i) {
            var clipPct = entry.status === "done" ? 0 : 100 - entry.progress;
            return React.createElement("div", {
              key: i,
              style: {
                position: "relative", aspectRatio: "16/9",
                borderRadius: 6, overflow: "hidden",
                background: "var(--s3)",
              }
            },
              // Grayscale base layer
              React.createElement("img", {
                src: entry.previewUrl,
                style: {
                  position: "absolute", inset: 0,
                  width: "100%", height: "100%",
                  objectFit: "cover",
                  filter: "grayscale(1)",
                }
              }),
              // Color reveal top layer
              React.createElement("img", {
                src: entry.previewUrl,
                style: {
                  position: "absolute", inset: 0,
                  width: "100%", height: "100%",
                  objectFit: "cover",
                  clipPath: "inset(" + clipPct + "% 0 0 0)",
                  transition: "clip-path 0.1s linear",
                }
              }),
              // Error overlay
              entry.status === "error" && React.createElement("div", {
                style: {
                  position: "absolute", inset: 0,
                  background: "rgba(248,113,113,0.7)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 11, color: "#fff", padding: 4, textAlign: "center",
                }
              }, entry.error || "Failed")
            );
          }),
          // Add more button
          React.createElement("div", {
            style: Object.assign({}, {
              aspectRatio: "16/9", borderRadius: 6,
              border: "1.5px dashed var(--b2)",
              display: "flex", alignItems: "center", justifyContent: "center",
              cursor: "pointer", color: "var(--t5)", fontSize: 22,
            }),
            onClick: function () { inputRef.current && inputRef.current.click(); },
          }, React.createElement("i", { className: "fa-solid fa-plus" }))
        ),

        // Actions
        React.createElement("div", { style: { display: "flex", gap: 8, justifyContent: "flex-end" } },
          React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 13 },
            onClick: onClose,
            disabled: anyUploading,
          }, "Cancel"),
          allDone && React.createElement("button", {
            className: "btn-primary",
            style: { fontSize: 13 },
            onClick: handleContinue,
          }, "Continue"),
        ),

        // Hidden file input
        React.createElement("input", {
          ref: inputRef,
          type: "file",
          accept: "image/jpeg,image/png,image/gif,image/webp",
          multiple: true,
          style: { display: "none" },
          onChange: function (e) { if (e.target.files.length) handleFiles(e.target.files); },
        })
      )
    );
  }

  // ─── Tag selector ─────────────────────────────────────────────────────────

  function TagSelector({ tags, selectedIds, onChange, maxTags }) {
    var limit = maxTags || 5;

    function toggle(id) {
      if (selectedIds.indexOf(id) >= 0) {
        onChange(selectedIds.filter(function (x) { return x !== id; }));
      } else if (selectedIds.length < limit) {
        onChange(selectedIds.concat([id]));
      }
    }

    if (!tags || tags.length === 0) {
      return React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "No tags available.");
    }

    return React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 6 } },
      tags.map(function (tag) {
        var selected = selectedIds.indexOf(tag.id) >= 0;
        return React.createElement("div", {
          key: tag.id,
          onClick: function () { toggle(tag.id); },
          style: {
            display: "inline-flex", alignItems: "center", gap: 5,
            padding: "3px 10px", borderRadius: 20, cursor: "pointer",
            border: "0.5px solid " + (selected ? tag.color : "var(--b2)"),
            background: selected ? tag.color + "22" : "transparent",
            color: selected ? tag.color : "var(--t4)",
            fontSize: 12, fontWeight: selected ? 500 : 400,
          }
        },
          React.createElement("div", {
            style: { width: 7, height: 7, borderRadius: "50%", background: tag.color, flexShrink: 0 }
          }),
          tag.name
        );
      })
    );
  }

  // ─── Metadata form (rendered at /new/:uuid) ───────────────────────────────

  function NewGalleryItemPage(props) {
    var uuid = props.uuid;
    var _item = useState(null);
    var item = _item[0]; var setItem = _item[1];
    var _tags = useState([]);
    var tags = _tags[0]; var setTags = _tags[1];
    var _loading = useState(true);
    var loading = _loading[0]; var setLoading = _loading[1];
    var _saving = useState(false);
    var saving = _saving[0]; var setSaving = _saving[1];
    var _form = useState({ title: "", description: "", is_draft: false, tag_ids: [] });
    var form = _form[0]; var setForm = _form[1];
    var _permissions = useState({});
    var permissions = _permissions[0]; var setPermissions = _permissions[1];

    useEffect(function () {
      Promise.all([
        apiGet("/items/" + uuid),
        apiGet("/tags"),
        apiGet("/permissions"),
      ]).then(function (results) {
        var itemData = results[0];
        var tagsData = results[1];
        var permsData = results[2];

        if (itemData.item) {
          setItem(itemData.item);
          setForm(function (p) { return Object.assign({}, p, {
            title:       itemData.item.title || "",
            description: itemData.item.description || "",
            tag_ids:     (itemData.item.tags || []).map(function (t) { return t.id; }),
          }); });
        }
        if (tagsData.tags) setTags(tagsData.tags);
        if (permsData.permissions) setPermissions(permsData.permissions);
        setLoading(false);
      }).catch(function () {
        setLoading(false);
      });
    }, [uuid]);

    function handleSave(isDraft) {
      setSaving(true);
      var attrs = Object.assign({}, form, { is_draft: isDraft });
      apiPatch("/items/" + uuid, attrs)
        .then(function (d) {
          if (d.item) {
            toast(isDraft ? "Saved as draft" : "Published!");
            if (!isDraft) {
              window.NexusExtensions.navigate("/ext/" + SLUG + "/" + uuid);
            }
          } else {
            toast(d.error || "Failed to save", "err");
          }
        })
        .catch(function () { toast("Failed to save", "err"); })
        .finally(function () { setSaving(false); });
    }

    if (loading) {
      return React.createElement("div", {
        style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" }
      }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }));
    }

    if (!item) {
      return React.createElement("div", {
        style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 14 }
      }, "Item not found.");
    }

    var labelStyle = { fontSize: 12, color: "var(--t4)", fontWeight: 500, display: "block", marginBottom: 6 };
    var inputStyle = {
      width: "100%", padding: "10px 14px",
      background: "rgba(255,255,255,0.05)", border: "0.5px solid var(--b2)",
      borderRadius: 10, color: "var(--t1)", fontSize: 14,
      outline: "none", fontFamily: "inherit",
    };

    return React.createElement("div", { style: { padding: "24px 0", maxWidth: 640 } },

      // Preview thumbnail
      item.file_url && React.createElement("div", {
        style: { marginBottom: 24, borderRadius: 10, overflow: "hidden", aspectRatio: "16/9", background: "var(--s2)" }
      },
        React.createElement("img", {
          src: item.file_url,
          style: { width: "100%", height: "100%", objectFit: "cover", display: "block" }
        })
      ),

      // Title
      React.createElement("div", { style: { marginBottom: 18 } },
        React.createElement("label", { style: labelStyle }, "Title"),
        React.createElement("input", {
          style: inputStyle,
          value: form.title,
          placeholder: "Give your image a title",
          onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { title: e.target.value }); }); },
        })
      ),

      // Description
      React.createElement("div", { style: { marginBottom: 18 } },
        React.createElement("label", { style: labelStyle }, "Description"),
        React.createElement("textarea", {
          style: Object.assign({}, inputStyle, { resize: "vertical", minHeight: 80 }),
          value: form.description,
          placeholder: "Optional description",
          rows: 3,
          onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { description: e.target.value }); }); },
        })
      ),

      // Tags
      tags.length > 0 && React.createElement("div", { style: { marginBottom: 24 } },
        React.createElement("label", { style: labelStyle }, "Tags"),
        React.createElement(TagSelector, {
          tags: tags,
          selectedIds: form.tag_ids,
          onChange: function (ids) { setForm(function (p) { return Object.assign({}, p, { tag_ids: ids }); }); },
          maxTags: 5,
        })
      ),

      // Actions
      React.createElement("div", { style: { display: "flex", gap: 8 } },
        React.createElement("button", {
          className: "btn-primary",
          style: { fontSize: 13, padding: "8px 20px" },
          onClick: function () { handleSave(false); },
          disabled: saving,
        }, saving ? "Publishing…" : "Publish"),
        React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 13, padding: "8px 16px" },
          onClick: function () { handleSave(true); },
          disabled: saving,
        }, "Save as draft"),
        React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 13, padding: "8px 16px", marginLeft: "auto" },
          onClick: function () { window.NexusExtensions.navigate("/ext/" + SLUG); },
          disabled: saving,
        }, "Discard")
      )
    );
  }

  // ─── Gallery browse page (placeholder — Phase 4) ──────────────────────────

  function GalleryPage(props) {
    var _showUpload = useState(false);
    var showUpload = _showUpload[0]; var setShowUpload = _showUpload[1];
    var _permissions = useState({});
    var permissions = _permissions[0]; var setPermissions = _permissions[1];

    useEffect(function () {
      apiGet("/permissions").then(function (d) {
        if (d.permissions) setPermissions(d.permissions);
      }).catch(function () {});
    }, []);

    return React.createElement("div", { style: { padding: "24px 0" } },
      showUpload && React.createElement(UploadModal, {
        onClose: function () { setShowUpload(false); },
        onUploaded: function () { setShowUpload(false); },
      }),

      // Toolbar
      React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 8, marginBottom: 24 } },
        permissions.can_upload_image && React.createElement("button", {
          className: "btn-primary",
          style: { fontSize: 13, display: "flex", alignItems: "center", gap: 6 },
          onClick: function () { setShowUpload(true); },
        },
          React.createElement("i", { className: "fa-solid fa-upload", style: { fontSize: 12 } }),
          " Upload"
        ),
        permissions.can_create_collection && React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 13, display: "flex", alignItems: "center", gap: 6 },
          onClick: function () {},
        },
          React.createElement("i", { className: "fa-solid fa-layer-group", style: { fontSize: 12 } }),
          " New collection"
        )
      ),

      // Phase 4 placeholder
      React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 } },
        React.createElement("i", { className: "fa-solid fa-images", style: { fontSize: 32, display: "block", marginBottom: 12, color: "var(--t5)" } }),
        React.createElement("div", null, "Gallery browse coming in Phase 4.")
      )
    );
  }

  // ─── Remaining route placeholders ────────────────────────────────────────

  function Placeholder(props) {
    return React.createElement("div",
      { style: { padding: "48px 0", textAlign: "center", color: "var(--t4)", fontSize: 14 } },
      React.createElement("i", { className: "fa-solid fa-images", style: { fontSize: 32, display: "block", marginBottom: 16, color: "var(--t5)" } }),
      React.createElement("div", { style: { fontWeight: 500, color: "var(--t2)", marginBottom: 8 } }, props.title || "Gallery"),
      React.createElement("div", null, "Coming in a future phase.")
    );
  }

  function GalleryItemPage()    { return React.createElement(Placeholder, { title: "Gallery item" }); }
  function CollectionPage()     { return React.createElement(Placeholder, { title: "Collection" }); }
  function GalleryTagPage()     { return React.createElement(Placeholder, { title: "Gallery tag" }); }
  function GalleryUserPage()    { return React.createElement(Placeholder, { title: "Gallery uploads" }); }

  // ─── Admin panel ─────────────────────────────────────────────────────────

  function TagForm(props) {
    var initial  = props.initial;
    var onSave   = props.onSave;
    var onCancel = props.onCancel;
    var defaults = initial || { name: "", color: "#7c5cfc", allow_images: true, allow_videos: true, allow_embeds: true };
    var _s = useState(defaults);
    var form = _s[0]; var setForm = _s[1];
    var _saving = useState(false);
    var saving = _saving[0]; var setSaving = _saving[1];

    function handleSubmit() {
      if (!form.name.trim()) { toast("Name is required", "err"); return; }
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

    return React.createElement("div", {
      style: { background: "var(--s2)", border: "0.5px solid var(--b2)", borderRadius: 12, padding: "16px 18px", marginBottom: 10 }
    },
      React.createElement("div", { style: { marginBottom: 14 } },
        React.createElement("div", { style: sectionStyle }, "Name"),
        React.createElement("input", {
          style: inputStyle, value: form.name, placeholder: "Tag name", autoFocus: true,
          onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { name: e.target.value }); }); },
        })
      ),
      React.createElement("div", { style: { marginBottom: 14 } },
        React.createElement("div", { style: sectionStyle }, "Color"),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10 } },
          React.createElement("input", {
            style: Object.assign({}, inputStyle, { maxWidth: 130 }), value: form.color, placeholder: "#7c5cfc",
            onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); },
          }),
          React.createElement("input", {
            type: "color", value: form.color || "#7c5cfc",
            onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); },
            style: { width: 36, height: 36, border: "none", borderRadius: 6, cursor: "pointer", background: "none" },
          }),
          React.createElement("div", { style: { width: 28, height: 28, borderRadius: "50%", background: form.color || "#7c5cfc", flexShrink: 0 } })
        )
      ),
      React.createElement("div", { style: { marginBottom: 16 } },
        React.createElement("div", { style: sectionStyle }, "Allowed media types"),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10, padding: "6px 0" } },
          React.createElement(Toggle, { value: form.allow_images, onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_images: v }); }); }, label: "Images" })
        ),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10, padding: "6px 0" } },
          React.createElement(Toggle, { value: form.allow_videos, onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_videos: v }); }); }, label: "Videos" })
        ),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10, padding: "6px 0" } },
          React.createElement(Toggle, { value: form.allow_embeds, onChange: function (v) { setForm(function (p) { return Object.assign({}, p, { allow_embeds: v }); }); }, label: "Embeds" })
        )
      ),
      React.createElement("div", { style: { display: "flex", gap: 8 } },
        React.createElement("button", { className: "btn-primary", style: { fontSize: 13, padding: "7px 16px" }, onClick: handleSubmit, disabled: saving },
          saving ? "Saving…" : (initial ? "Save changes" : "Create tag")),
        React.createElement("button", { className: "btn-ghost", style: { fontSize: 13, padding: "7px 16px" }, onClick: onCancel, disabled: saving }, "Cancel")
      )
    );
  }

  function TagRow(props) {
    var tag = props.tag; var onEdit = props.onEdit; var onDelete = props.onDelete;
    var badgeStyle = function (color, active) {
      return {
        fontSize: 10, padding: "1px 6px", borderRadius: 4, fontWeight: 500,
        background: active ? color + "22" : "rgba(255,255,255,0.04)",
        color: active ? color : "var(--t5)",
        border: "0.5px solid " + (active ? color + "44" : "var(--b1)"),
      };
    };
    return React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10, padding: "10px 0", borderBottom: "0.5px solid var(--b1)" } },
      React.createElement("div", { style: { color: "var(--t5)", cursor: "grab", fontSize: 13, flexShrink: 0 } },
        React.createElement("i", { className: "fa-solid fa-grip-vertical" })
      ),
      React.createElement("div", { style: { width: 10, height: 10, borderRadius: "50%", background: tag.color, flexShrink: 0 } }),
      React.createElement("span", { style: { fontSize: 13, color: "var(--t2)", fontWeight: 500, flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, tag.name),
      React.createElement("div", { style: { display: "flex", gap: 4 } },
        React.createElement("span", { style: badgeStyle("#60a5fa", tag.allow_images) }, "IMG"),
        React.createElement("span", { style: badgeStyle("#fbbf24", tag.allow_videos) }, "VID"),
        React.createElement("span", { style: badgeStyle("#a78bfa", tag.allow_embeds) }, "EMB")
      ),
      React.createElement("span", { style: { fontSize: 11.5, color: "var(--t5)", minWidth: 28, textAlign: "right", flexShrink: 0 } }, tag.item_count),
      React.createElement("button", {
        onClick: function () { onEdit(tag); },
        style: { fontSize: 11.5, padding: "3px 9px", borderRadius: 8, border: "0.5px solid var(--b2)", color: "var(--t4)", background: "transparent", cursor: "pointer", fontFamily: "inherit" }
      }, React.createElement("i", { className: "fa-solid fa-pen" })),
      React.createElement("button", {
        onClick: function () { onDelete(tag); },
        style: { fontSize: 11.5, padding: "3px 9px", borderRadius: 8, border: "0.5px solid rgba(248,113,113,0.3)", color: "var(--red)", background: "transparent", cursor: "pointer", fontFamily: "inherit" }
      }, React.createElement("i", { className: "fa-solid fa-trash" }))
    );
  }

  function TagsTab() {
    var _tags = useState(null); var tags = _tags[0]; var setTags = _tags[1];
    var _loading = useState(true); var loading = _loading[0]; var setLoading = _loading[1];
    var _creating = useState(false); var creating = _creating[0]; var setCreating = _creating[1];
    var _editing = useState(null); var editing = _editing[0]; var setEditing = _editing[1];
    var dragIndex = useRef(null); var dragOverIndex = useRef(null);

    function load() {
      setLoading(true);
      apiGet("/tags").then(function (d) { setTags(d.tags || []); setLoading(false); })
        .catch(function () { toast("Failed to load tags", "err"); setLoading(false); });
    }
    useEffect(load, []);

    function handleCreate(form) {
      return apiPost("/tags", form).then(function (d) {
        if (d.tag) { setTags(function (p) { return p.concat(d.tag); }); setCreating(false); toast("Tag created"); }
        else toast(d.error || "Failed to create tag", "err");
      });
    }
    function handleEdit(form) {
      return apiPatch("/tags/" + editing.id, form).then(function (d) {
        if (d.tag) { setTags(function (p) { return p.map(function (t) { return t.id === d.tag.id ? d.tag : t; }); }); setEditing(null); toast("Tag updated"); }
        else toast(d.error || "Failed to update tag", "err");
      });
    }
    function handleDelete(tag) {
      if (!window.confirm("Delete tag \"" + tag.name + "\"? This cannot be undone.")) return;
      apiDelete("/tags/" + tag.id).then(function (d) {
        if (d.ok) { setTags(function (p) { return p.filter(function (t) { return t.id !== tag.id; }); }); toast("Tag deleted"); }
        else toast(d.error || "Failed to delete tag", "err");
      });
    }
    function handleDragStart(i) { dragIndex.current = i; }
    function handleDragOver(e, i) { e.preventDefault(); dragOverIndex.current = i; }
    function handleDrop() {
      var from = dragIndex.current; var to = dragOverIndex.current;
      if (from === null || to === null || from === to) return;
      var reordered = tags.slice(); var moved = reordered.splice(from, 1)[0]; reordered.splice(to, 0, moved);
      setTags(reordered); dragIndex.current = null; dragOverIndex.current = null;
      apiPost("/tags/reorder", { ids: reordered.map(function (t) { return t.id; }) })
        .then(function (d) { if (!d.ok) toast("Failed to save order", "err"); })
        .catch(function () { toast("Failed to save order", "err"); });
    }

    if (loading) return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" } }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }));

    return React.createElement("div", null,
      React.createElement("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 } },
        React.createElement("div", { style: { fontSize: 13, color: "var(--t4)" } }, tags ? tags.length + " tag" + (tags.length === 1 ? "" : "s") + " · drag to reorder" : ""),
        !creating && React.createElement("button", { className: "btn-ghost", style: { fontSize: 12.5, display: "flex", alignItems: "center", gap: 6 }, onClick: function () { setCreating(true); setEditing(null); } },
          React.createElement("i", { className: "fa-solid fa-plus" }), " New tag")
      ),
      creating && React.createElement(TagForm, { onSave: handleCreate, onCancel: function () { setCreating(false); } }),
      tags && tags.length === 0 && !creating && React.createElement("div", { style: { padding: "32px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 } }, "No tags yet. Create one to get started."),
      tags && tags.map(function (tag, index) {
        if (editing && editing.id === tag.id) return React.createElement(TagForm, { key: tag.id, initial: tag, onSave: handleEdit, onCancel: function () { setEditing(null); } });
        return React.createElement("div", { key: tag.id, draggable: true, onDragStart: function () { handleDragStart(index); }, onDragOver: function (e) { handleDragOver(e, index); }, onDrop: handleDrop },
          React.createElement(TagRow, { tag: tag, onEdit: function (t) { setEditing(t); setCreating(false); }, onDelete: handleDelete })
        );
      })
    );
  }

  function ComingSoonTab(props) {
    return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 } },
      React.createElement("i", { className: "fa-solid fa-clock", style: { fontSize: 28, display: "block", marginBottom: 12 } }),
      (props.label || "This tab") + " coming in a future phase."
    );
  }

  function GalleryAdminPanel() {
    var _ref = window.NexusExtensionTemplates;
    var SimpleSettingsPanel = _ref.SimpleSettingsPanel;
    var TabbedPanel = _ref.TabbedPanel;

    return React.createElement(TabbedPanel, {
      tabs: [
        {
          key: "general", label: "General", icon: "fa-gear",
          render: function () {
            return React.createElement(SimpleSettingsPanel, {
              slug: SLUG,
              fields: [
                { key: "gallery_enabled",         label: "Gallery enabled",       type: "boolean", hint: "Show Gallery in the Explore sidebar and make all routes accessible." },
                { key: "ratings_enabled",          label: "Ratings enabled",       type: "boolean", hint: "Allow members to give 1–5 star ratings on images, videos, and collections." },
                { key: "comments_enabled",         label: "Comments enabled",      type: "boolean", hint: "Allow members to comment on gallery items and collections." },
                { key: "reactions_enabled",        label: "Reactions enabled",     type: "boolean", hint: "Allow members to react to gallery items and collections with emoji." },
                { key: "moderation_queue_enabled", label: "Moderation queue",      type: "boolean", hint: "New uploads go into a pending queue and require admin approval before appearing publicly." },
                { key: "max_tags_per_item",        label: "Max tags per item",     type: "number",  hint: "Maximum number of tags a member can apply to a single image, video, or embed." },
                { key: "max_collection_size",      label: "Max collection size",   type: "number",  hint: "Maximum number of items a collection can contain." },
                { key: "items_per_page",           label: "Items per page",        type: "select",  options: [{ value: "24", label: "24" }, { value: "36", label: "36" }, { value: "48", label: "48" }, { value: "60", label: "60" }] },
                { key: "videos_enabled",           label: "Video uploads enabled", type: "boolean", hint: "Allow members to upload video files (MP4, WebM). Disabled by default — requires sufficient storage." },
                { key: "max_video_size_mb",        label: "Max video size (MB)",   type: "number",  hint: "Per-file size cap for video uploads. Nexus's global upload limit also applies." },
              ],
            });
          },
        },
        { key: "tags",    label: "Tags",    icon: "fa-tag",      render: function () { return React.createElement(TagsTab); } },
        { key: "queue",   label: "Queue",   icon: "fa-clock",    render: function () { return React.createElement(ComingSoonTab, { label: "Moderation queue" }); } },
        { key: "harvest", label: "Harvest", icon: "fa-seedling", render: function () { return React.createElement(ComingSoonTab, { label: "Image harvest configuration" }); } },
        { key: "stats",   label: "Stats",   icon: "fa-chart-bar",render: function () { return React.createElement(ComingSoonTab, { label: "Gallery stats" }); } },
      ],
    });
  }

  // ─── Right widgets (stubs) ────────────────────────────────────────────────

  function GalleryStatsWidget()        { return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Gallery"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Stats coming soon.")); }
  function GalleryTopRatedWidget()     { return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Top rated"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")); }
  function GalleryTagsWidget()         { return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Tags"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")); }
  function GalleryTopUploadersWidget() { return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Top uploaders"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")); }

  function GalleryProfileTab(props) { return React.createElement(Placeholder, { title: "Gallery uploads for " + (props.username || "") }); }

  // ─── Register all surfaces ────────────────────────────────────────────────

  NE.registerRoute(SLUG, "/",                 GalleryPage,        { title: "Gallery" });
  NE.registerRoute(SLUG, "/:uuid",            GalleryItemPage,    { title: "Gallery item" });
  NE.registerRoute(SLUG, "/collection/:slug", CollectionPage,     { title: "Collection" });
  NE.registerRoute(SLUG, "/tag/:slug",        GalleryTagPage,     { title: "Gallery tag" });
  NE.registerRoute(SLUG, "/user/:username",   GalleryUserPage,    { title: "Gallery uploads" });
  NE.registerRoute(SLUG, "/new/:uuid",        NewGalleryItemPage, { title: "New gallery item" });

  NE.registerAdminPanel(SLUG, { label: "Gallery", icon: "fa-images", component: GalleryAdminPanel });

  NE.registerExploreItem({ slug: SLUG, path: "/", label: "Gallery", icon: "fa-images", authOnly: false, priority: 50 });

  NE.registerRightWidget({ slug: SLUG, id: "gallery-stats",         label: "Gallery stats",         component: GalleryStatsWidget,        scope: "extension", priority: 10 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-top-rated",     label: "Gallery top rated",     component: GalleryTopRatedWidget,     scope: "extension", priority: 20 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-tags",          label: "Gallery tags",          component: GalleryTagsWidget,         scope: "extension", priority: 30 });
  NE.registerRightWidget({ slug: SLUG, id: "gallery-top-uploaders", label: "Gallery top uploaders", component: GalleryTopUploadersWidget, scope: "extension", priority: 40 });

  NE.registerProfileTab({ slug: SLUG, id: "gallery-uploads", component: GalleryProfileTab });

  NE.registerNotificationType("gallery_comment",   { icon: "fa-comment", iconColor: "var(--ac)", renderBody: function (n) { return React.createElement(React.Fragment, null, React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"), React.createElement("span", { style: { color: "var(--t3)" } }, " commented on your gallery item.")); }, onClick: function () {} });
  NE.registerNotificationType("gallery_rating",    { icon: "fa-star",    iconColor: "var(--ac)", renderBody: function (n) { return React.createElement(React.Fragment, null, React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"), React.createElement("span", { style: { color: "var(--t3)" } }, " rated your gallery item.")); }, onClick: function () {} });
  NE.registerNotificationType("gallery_new_image", { icon: "fa-images",  iconColor: "var(--ac)", renderBody: function (n) { return React.createElement(React.Fragment, null, React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"), React.createElement("span", { style: { color: "var(--t3)" } }, " added a new image to a tag you follow.")); }, onClick: function () {} });

})();
