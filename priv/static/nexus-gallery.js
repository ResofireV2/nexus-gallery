(function () {
  "use strict";

  const NE   = window.NexusExtensions;
  const SLUG = "nexus-gallery";
  const { useState, useEffect, useRef, useCallback } = window.React;
  const { Toggle, toast, Av, Md } = window.NexusComponents;

  // ─── Shared fetch helpers ─────────────────────────────────────────────────

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

  // ─── XHR upload (progress events) ────────────────────────────────────────

  function uploadFileXhr(file, recordId, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr  = new XMLHttpRequest();
      var body = new FormData();
      body.append("file", file);
      body.append("type", "extension_image");
      if (recordId) body.append("record_id", recordId);

      xhr.upload.onprogress = function (e) {
        if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100));
      };
      xhr.onload = function () {
        try {
          var r = JSON.parse(xhr.responseText);
          if (r.url) resolve(r);
          else reject(new Error(r.error || "Upload failed"));
        } catch (_) { reject(new Error("Invalid upload response")); }
      };
      xhr.onerror = function () { reject(new Error("Network error during upload")); };

      var token = localStorage.getItem("nexus_token");
      xhr.open("POST", "/api/v1/uploads/ext/" + SLUG);
      if (token) xhr.setRequestHeader("authorization", "Bearer " + token);
      xhr.send(body);
    });
  }

  // ─── Upload modal ─────────────────────────────────────────────────────────

  function UploadModal(props) {
    var onClose    = props.onClose;
    var onUploaded = props.onUploaded;

    var _entries = useState([]); var entries = _entries[0]; var setEntries = _entries[1];
    var inputRef = useRef(null);

    function handleFiles(files) {
      var idx0 = entries.length;
      var newEntries = Array.from(files).map(function (f) {
        return { file: f, previewUrl: URL.createObjectURL(f), status: "pending", progress: 0,
                 url: null, originalUrl: null, uploadId: null, error: null, draftId: null };
      });
      setEntries(function (prev) { return prev.concat(newEntries); });
      newEntries.forEach(function (entry, i) { startUpload(idx0 + i, entry); });
    }

    function startUpload(idx, entry) {
      apiPost("/items/draft", { media_type: "image" })
        .then(function (d) {
          if (!d.id) throw new Error(d.error || "Failed to create draft");
          var draftId = d.id;
          setEntries(function (prev) {
            var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { status: "uploading", draftId: draftId }); return u;
          });
          return uploadFileXhr(entry.file, draftId, function (pct) {
            setEntries(function (prev) {
              var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { progress: pct }); return u;
            });
          }).then(function (r) {
            // Save file_url, original_url and upload_id back to the draft item
            // so the detail page can display the image when it loads.
            // draftId is in scope here because this .then() is nested inside
            // the outer .then() where draftId was declared.
            return apiPatch("/items/" + draftId, {
              file_url:     r.url,
              original_url: r.original_url,
              upload_id:    r.upload ? r.upload.id : null,
            }).then(function () {
              setEntries(function (prev) {
                var u = prev.slice();
                u[idx] = Object.assign({}, u[idx], { status: "done", progress: 100, url: r.url, originalUrl: r.original_url, uploadId: r.upload && r.upload.id });
                return u;
              });
            });
          });
        })
        .catch(function (err) {
          setEntries(function (prev) {
            var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { status: "error", progress: 0, error: err.message }); return u;
          });
          toast(err.message || "Upload failed", "err");
        });
    }

    function handleDrop(e) { e.preventDefault(); if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files); }

    var allDone      = entries.length > 0 && entries.every(function (e) { return e.status === "done"; });
    var anyUploading = entries.some(function (e) { return e.status === "uploading" || e.status === "pending"; });

    function handleContinue() {
      var done = entries.filter(function (e) { return e.status === "done" && e.draftId; });
      if (done.length === 0) return;
      onClose();
      NE.navigate("/ext/" + SLUG + "/new/" + done[0].draftId);
    }

    return React.createElement("div", {
      style: { position: "fixed", inset: 0, background: "rgba(0,0,0,0.6)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 9000 },
      onClick: function (e) { if (e.target === e.currentTarget && !anyUploading) onClose(); }
    },
      React.createElement("div", {
        style: { background: "var(--s2)", border: "0.5px solid var(--b2)", borderRadius: 14, padding: 24, width: 540, maxWidth: "calc(100vw - 32px)", maxHeight: "80vh", overflow: "hidden", display: "flex", flexDirection: "column", gap: 16 }
      },
        React.createElement("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between" } },
          React.createElement("span", { style: { fontSize: 15, fontWeight: 500, color: "var(--t1)" } }, "Upload images"),
          React.createElement("button", { onClick: onClose, disabled: anyUploading, style: { background: "none", border: "none", color: "var(--t4)", cursor: "pointer", fontSize: 18 } },
            React.createElement("i", { className: "fa-solid fa-xmark" }))
        ),
        entries.length === 0 && React.createElement("div", {
          style: { border: "1.5px dashed var(--b2)", borderRadius: 10, padding: "32px 24px", textAlign: "center", cursor: "pointer", color: "var(--t4)", fontSize: 13 },
          onClick: function () { inputRef.current && inputRef.current.click(); },
          onDrop: handleDrop,
          onDragOver: function (e) { e.preventDefault(); }
        },
          React.createElement("i", { className: "fa-solid fa-upload", style: { fontSize: 28, display: "block", marginBottom: 10, color: "var(--t5)" } }),
          React.createElement("div", null, "Click to select images or drag and drop"),
          React.createElement("div", { style: { fontSize: 11, color: "var(--t5)", marginTop: 4 } }, "JPEG, PNG, GIF, WebP")
        ),
        entries.length > 0 && React.createElement("div", { style: { display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, overflowY: "auto", maxHeight: 260 } },
          entries.map(function (entry, i) {
            var clip = entry.status === "done" ? 0 : 100 - entry.progress;
            return React.createElement("div", { key: i, style: { position: "relative", aspectRatio: "16/9", borderRadius: 6, overflow: "hidden", background: "var(--s3)" } },
              React.createElement("img", { src: entry.previewUrl, style: { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", filter: "grayscale(1)" } }),
              React.createElement("img", { src: entry.previewUrl, style: { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", clipPath: "inset(" + clip + "% 0 0 0)", transition: "clip-path 0.1s linear" } }),
              entry.status === "error" && React.createElement("div", { style: { position: "absolute", inset: 0, background: "rgba(248,113,113,0.7)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "#fff", padding: 4, textAlign: "center" } }, entry.error || "Failed")
            );
          }),
          React.createElement("div", {
            style: { aspectRatio: "16/9", borderRadius: 6, border: "1.5px dashed var(--b2)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", color: "var(--t5)", fontSize: 22 },
            onClick: function () { inputRef.current && inputRef.current.click(); }
          }, React.createElement("i", { className: "fa-solid fa-plus" }))
        ),
        React.createElement("div", { style: { display: "flex", gap: 8, justifyContent: "flex-end" } },
          React.createElement("button", { className: "btn-ghost", style: { fontSize: 13 }, onClick: onClose, disabled: anyUploading }, "Cancel"),
          allDone && React.createElement("button", { className: "btn-primary", style: { fontSize: 13 }, onClick: handleContinue }, "Continue")
        ),
        React.createElement("input", { ref: inputRef, type: "file", accept: "image/jpeg,image/png,image/gif,image/webp", multiple: true, style: { display: "none" }, onChange: function (e) { if (e.target.files.length) handleFiles(e.target.files); } })
      )
    );
  }

  // ─── Tag selector ─────────────────────────────────────────────────────────

  function TagSelector(props) {
    var tags = props.tags; var selectedIds = props.selectedIds; var onChange = props.onChange; var maxTags = props.maxTags || 5;
    function toggle(id) {
      if (selectedIds.indexOf(id) >= 0) onChange(selectedIds.filter(function (x) { return x !== id; }));
      else if (selectedIds.length < maxTags) onChange(selectedIds.concat([id]));
    }
    if (!tags || tags.length === 0) return React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "No tags available.");
    return React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 6 } },
      tags.map(function (tag) {
        var sel = selectedIds.indexOf(tag.id) >= 0;
        return React.createElement("div", {
          key: tag.id, onClick: function () { toggle(tag.id); },
          style: { display: "inline-flex", alignItems: "center", gap: 5, padding: "3px 10px", borderRadius: 20, cursor: "pointer", border: "0.5px solid " + (sel ? tag.color : "var(--b2)"), background: sel ? tag.color + "22" : "transparent", color: sel ? tag.color : "var(--t4)", fontSize: 12, fontWeight: sel ? 500 : 400 }
        },
          React.createElement("div", { style: { width: 7, height: 7, borderRadius: "50%", background: tag.color, flexShrink: 0 } }),
          tag.name
        );
      })
    );
  }

  // ─── Gallery card ─────────────────────────────────────────────────────────

  function GalleryCard(props) {
    var item     = props.item;
    var navigate = props.navigate;

    var thumb = item.thumbnail_url || item.file_url;
    var isYT  = item.media_type === "embed" && item.embed_url && item.embed_url.indexOf("youtu") >= 0;

    // Extract YouTube thumbnail from embed_url if no explicit thumbnail
    if (!thumb && isYT) {
      var m = item.embed_url.match(/(?:youtu\.be\/|v=|embed\/)([A-Za-z0-9_-]{11})/);
      if (m) thumb = "https://i.ytimg.com/vi/" + m[1] + "/mqdefault.jpg";
    }

    function handleClick() {
      NE.navigate("/ext/" + SLUG + "/" + item.id);
    }

    var mediaIcon = null;
    if (item.media_type === "video") mediaIcon = React.createElement("i", { className: "fa-solid fa-video" });
    if (item.media_type === "embed") mediaIcon = React.createElement("i", { className: "fa-brands fa-youtube" });

    return React.createElement("div", {
      onClick: handleClick,
      style: { borderRadius: 10, overflow: "hidden", border: "0.5px solid var(--b1)", background: "var(--s1)", cursor: "pointer" }
    },
      React.createElement("div", { style: { position: "relative", width: "100%", aspectRatio: "16/9", background: "var(--s2)", overflow: "hidden" } },
        thumb && React.createElement("img", {
          src: thumb,
          style: { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", display: "block" },
          loading: "lazy"
        }),
        item.is_featured && React.createElement("div", {
          style: { position: "absolute", top: 6, left: 6, background: "rgba(124,92,252,0.85)", color: "#fff", fontSize: 9, padding: "2px 6px", borderRadius: 4, fontWeight: 500 }
        }, "★ Featured"),
        mediaIcon && React.createElement("div", {
          style: { position: "absolute", top: 6, right: 6, background: "rgba(0,0,0,0.6)", color: "rgba(255,255,255,0.9)", fontSize: 9.5, padding: "2px 6px", borderRadius: 4, display: "flex", alignItems: "center", gap: 3 }
        }, mediaIcon)
      ),
      React.createElement("div", { style: { padding: "8px 10px" } },
        React.createElement("div", { style: { fontSize: 12.5, fontWeight: 500, color: "var(--t2)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } },
          item.title || React.createElement("span", { style: { color: "var(--t5)" } }, "Untitled")
        ),
        React.createElement("div", { style: { fontSize: 11, color: "var(--t5)", marginTop: 3, display: "flex", alignItems: "center", gap: 6 } },
          item.user && React.createElement(Av, { user: item.user, size: 14 }),
          item.user && React.createElement("span", null, item.user.username),
          React.createElement("span", { style: { marginLeft: "auto", display: "flex", alignItems: "center", gap: 3 } },
            React.createElement("i", { className: "fa-solid fa-eye", style: { fontSize: 9 } }),
            item.view_count || 0
          )
        )
      )
    );
  }

  // ─── Gallery browse page ──────────────────────────────────────────────────

  function GalleryPage(props) {
    var currentUser = props.currentUser;

    var _showUpload          = useState(false); var showUpload          = _showUpload[0];          var setShowUpload          = _showUpload[1];
    var _showNewCollection   = useState(false); var showNewCollection   = _showNewCollection[0];   var setShowNewCollection   = _showNewCollection[1];
    var _permissions       = useState({});  var permissions       = _permissions[0];       var setPermissions       = _permissions[1];
    var _gallerySettings   = useState({});  var gallerySettings   = _gallerySettings[0];   var setGallerySettings   = _gallerySettings[1];
    var _items          = useState([]);       var items          = _items[0];          var setItems          = _items[1];
    var _tags           = useState([]);       var tags           = _tags[0];           var setTags           = _tags[1];
    var _loading        = useState(true);     var loading        = _loading[0];        var setLoading        = _loading[1];
    var _total          = useState(0);        var total          = _total[0];          var setTotal          = _total[1];
    var _totalPages     = useState(1);        var totalPages     = _totalPages[0];     var setTotalPages     = _totalPages[1];
    var _activeTab      = useState("Images"); var activeTab      = _activeTab[0];      var setActiveTab      = _activeTab[1];
    var _sort           = useState("newest"); var sort           = _sort[0];           var setSort           = _sort[1];
    var _activeTag      = useState(null);     var activeTag      = _activeTag[0];      var setActiveTag      = _activeTag[1];
    var _page           = useState(1);        var page           = _page[0];           var setPage           = _page[1];
    var _search         = useState("");       var search         = _search[0];         var setSearch         = _search[1];
    var searchTimer     = useRef(null);

    var TAB_TYPE_MAP = { "Images": "image", "Videos": "video", "Embeds": "embed", "Collections": null };

    function loadItems(p, s, tag, tab, q) {
      setLoading(true);
      if (tab === "Collections") {
        var qs = "?page=" + (p || 1) + "&sort=" + (s || "newest");
        if (q) qs += "&search=" + encodeURIComponent(q);
        apiGet("/collections" + qs).then(function (d) {
          setItems(d.collections || []);
          setTotal(d.total || 0);
          setTotalPages(d.total_pages || 1);
          setLoading(false);
        }).catch(function () { setLoading(false); });
      } else {
        var mediaType = TAB_TYPE_MAP[tab];
        var qs = "?page=" + (p || 1) + "&sort=" + (s || "newest");
        if (tag)       qs += "&tag=" + encodeURIComponent(tag);
        if (mediaType) qs += "&type=" + mediaType;
        if (q)         qs += "&search=" + encodeURIComponent(q);
        apiGet("/items" + qs).then(function (d) {
          setItems(d.items || []);
          setTotal(d.total || 0);
          setTotalPages(d.total_pages || 1);
          setLoading(false);
        }).catch(function () { setLoading(false); });
      }
    }

    useEffect(function () {
      Promise.all([apiGet("/permissions"), apiGet("/tags/public")]).then(function (results) {
        if (results[0].permissions) setPermissions(results[0].permissions);
        if (results[0]) setGallerySettings(results[0]);
        if (results[1].tags)        setTags(results[1].tags);
      }).catch(function () {});
      loadItems(1, sort, activeTag, activeTab, search);
    }, []);

    function handleTabChange(tab) {
      setActiveTab(tab); setPage(1);
      loadItems(1, sort, activeTag, tab, search);
    }

    function handleSortChange(s) {
      setSort(s); setPage(1);
      loadItems(1, s, activeTag, activeTab, search);
    }

    function handleTagChange(slug) {
      var t = slug === activeTag ? null : slug;
      setActiveTag(t); setPage(1);
      loadItems(1, sort, t, activeTab, search);
    }

    function handleSearchChange(q) {
      setSearch(q);
      clearTimeout(searchTimer.current);
      searchTimer.current = setTimeout(function () {
        setPage(1);
        loadItems(1, sort, activeTag, activeTab, q);
      }, 350);
    }

    function handlePageChange(p) {
      setPage(p);
      loadItems(p, sort, activeTag, activeTab, search);
      window.scrollTo(0, 0);
    }

    var tabs = ["Images", "Collections", "Videos", "Embeds"];
    var sorts = [
      { key: "newest",         label: "Newest" },
      { key: "oldest",         label: "Oldest" },
      { key: "top_rated",      label: "Top rated" },
      { key: "most_commented", label: "Most commented" },
    ];

    return React.createElement("div", { style: { paddingBottom: 32 } },
      showUpload && React.createElement(UploadModal, {
        onClose: function () { setShowUpload(false); },
        onUploaded: function () { setShowUpload(false); },
      }),

      showNewCollection && React.createElement(NewCollectionModal, {
        onClose: function () { setShowNewCollection(false); },
        maxCollectionSize: gallerySettings.max_collection_size || 100,
        onCreated: function (coll) {
          setShowNewCollection(false);
          NE.navigate("/ext/" + SLUG + "/collection/" + coll.slug);
        },
      }),

      // Tab bar
      React.createElement("div", { style: { display: "flex", borderBottom: "0.5px solid var(--b1)", margin: "0 -28px", padding: "0 28px" } },
        tabs.map(function (tab) {
          return React.createElement("div", {
            key: tab,
            onClick: function () { handleTabChange(tab); },
            style: { padding: "10px 14px", fontSize: 12.5, color: activeTab === tab ? "var(--t1)" : "var(--t4)", cursor: "pointer", borderBottom: "2px solid " + (activeTab === tab ? "var(--ac)" : "transparent"), marginBottom: -0.5, fontWeight: activeTab === tab ? 500 : 400 }
          }, tab);
        })
      ),

      // Toolbar: sort + tag chips + search + upload button
      React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 6, padding: "10px 0", flexWrap: "wrap" } },
        // Sort pills
        sorts.map(function (s) {
          return React.createElement("div", {
            key: s.key, onClick: function () { handleSortChange(s.key); },
            style: { fontSize: 11.5, padding: "3px 10px", borderRadius: 20, border: "0.5px solid " + (sort === s.key ? "var(--ac)" : "var(--b2)"), background: sort === s.key ? "var(--ac)" : "transparent", color: sort === s.key ? "#fff" : "var(--t4)", cursor: "pointer" }
          }, s.label);
        }),
        React.createElement("div", { style: { width: "0.5px", height: 16, background: "var(--b2)", margin: "0 2px", flexShrink: 0 } }),
        // Tag chips
        React.createElement("div", {
          onClick: function () { handleTagChange(null); },
          style: { fontSize: 11.5, padding: "3px 10px", borderRadius: 20, border: "0.5px solid " + (!activeTag ? "var(--ac)" : "var(--b1)"), color: !activeTag ? "var(--ac-text)" : "var(--t4)", cursor: "pointer" }
        }, "All"),
        tags.slice(0, 6).map(function (tag) {
          var active = activeTag === tag.slug;
          return React.createElement("div", {
            key: tag.id, onClick: function () { handleTagChange(tag.slug); },
            style: { display: "inline-flex", alignItems: "center", gap: 5, fontSize: 11.5, padding: "3px 10px", borderRadius: 20, border: "0.5px solid " + (active ? tag.color : "var(--b1)"), color: active ? tag.color : "var(--t4)", cursor: "pointer" }
          },
            React.createElement("div", { style: { width: 7, height: 7, borderRadius: "50%", background: tag.color, flexShrink: 0 } }),
            tag.name
          );
        }),
        // Spacer
        React.createElement("div", { style: { flex: 1 } }),
        // Search
        React.createElement("input", {
          value: search,
          onChange: function (e) { handleSearchChange(e.target.value); },
          placeholder: "Search…",
          style: { padding: "5px 12px", background: "rgba(255,255,255,0.05)", border: "0.5px solid var(--b2)", borderRadius: 20, color: "var(--t1)", fontSize: 12.5, outline: "none", fontFamily: "inherit", width: 160 }
        }),
        // Upload button
        permissions.can_upload_image && React.createElement("button", {
          className: "btn-primary",
          style: { fontSize: 12.5, display: "flex", alignItems: "center", gap: 6, padding: "6px 14px" },
          onClick: function () { setShowUpload(true); }
        },
          React.createElement("i", { className: "fa-solid fa-upload", style: { fontSize: 11 } }),
          "Upload"
        ),
        // New collection button
        permissions.can_create_collection && React.createElement("button", {
          className: "btn-ghost",
          style: { fontSize: 12.5, display: "flex", alignItems: "center", gap: 6, padding: "6px 14px" },
          onClick: function () { setShowNewCollection(true); }
        },
          React.createElement("i", { className: "fa-solid fa-layer-group", style: { fontSize: 11 } }),
          "New collection"
        )
      ),

      // Grid
      loading
        ? React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" } },
            React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }))
        : items.length === 0
          ? React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 } },
              React.createElement("i", { className: activeTab === "Collections" ? "fa-solid fa-layer-group" : "fa-solid fa-images", style: { fontSize: 32, display: "block", marginBottom: 12 } }),
              activeTab === "Collections" ? "No collections yet." : "No items found."
            )
          : React.createElement("div", { style: { display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10, paddingTop: 12 } },
              activeTab === "Collections"
              ? items.map(function (coll) {
                  return React.createElement(CollectionCard, { key: coll.id, collection: coll });
                })
              : items.map(function (item) {
                  return React.createElement(GalleryCard, { key: item.id, item: item, navigate: NE.navigate });
                })
            ),

      // Pagination
      totalPages > 1 && React.createElement("div", { style: { display: "flex", justifyContent: "center", gap: 6, marginTop: 24 } },
        page > 1 && React.createElement("button", {
          className: "btn-ghost", style: { fontSize: 12.5 }, onClick: function () { handlePageChange(page - 1); }
        }, React.createElement("i", { className: "fa-solid fa-chevron-left" })),
        Array.from({ length: Math.min(totalPages, 7) }, function (_, i) {
          var p = i + 1;
          return React.createElement("button", {
            key: p, className: page === p ? "btn-primary" : "btn-ghost",
            style: { fontSize: 12.5, minWidth: 32 },
            onClick: function () { handlePageChange(p); }
          }, p);
        }),
        page < totalPages && React.createElement("button", {
          className: "btn-ghost", style: { fontSize: 12.5 }, onClick: function () { handlePageChange(page + 1); }
        }, React.createElement("i", { className: "fa-solid fa-chevron-right" }))
      ),

      // Item count
      !loading && total > 0 && React.createElement("div", {
        style: { textAlign: "center", fontSize: 11.5, color: "var(--t5)", marginTop: 12 }
      }, total + " item" + (total === 1 ? "" : "s"))
    );
  }

  // ─── Metadata form (New gallery item page) ────────────────────────────────

  function NewGalleryItemPage(props) {
    var uuid = props.uuid;

    var _item    = useState(null); var item    = _item[0];    var setItem    = _item[1];
    var _tags    = useState([]);   var tags    = _tags[0];    var setTags    = _tags[1];
    var _loading = useState(true); var loading = _loading[0]; var setLoading = _loading[1];
    var _saving  = useState(false);var saving  = _saving[0];  var setSaving  = _saving[1];
    var _form    = useState({ title: "", description: "", is_draft: false, tag_ids: [] });
    var form = _form[0]; var setForm = _form[1];

    useEffect(function () {
      Promise.all([apiGet("/items/" + uuid), apiGet("/tags/public")]).then(function (results) {
        if (results[0].item) {
          var i = results[0].item;
          setItem(i);
          setForm({ title: i.title || "", description: i.description || "", is_draft: false, tag_ids: (i.tags || []).map(function (t) { return t.id; }) });
        }
        if (results[1].tags) setTags(results[1].tags);
        setLoading(false);
      }).catch(function () { setLoading(false); });
    }, [uuid]);

    function handleSave(isDraft) {
      setSaving(true);
      apiPatch("/items/" + uuid, Object.assign({}, form, { is_draft: isDraft }))
        .then(function (d) {
          if (d.item) {
            toast(isDraft ? "Saved as draft" : "Published!");
            if (!isDraft) NE.navigate("/ext/" + SLUG + "/" + uuid);
          } else {
            toast(d.error || "Failed to save", "err");
          }
        })
        .catch(function () { toast("Failed to save", "err"); })
        .finally(function () { setSaving(false); });
    }

    if (loading) return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" } }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }));
    if (!item)   return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)", fontSize: 14 } }, "Item not found.");

    var labelStyle = { fontSize: 12, color: "var(--t4)", fontWeight: 500, display: "block", marginBottom: 6 };
    var inputStyle = { width: "100%", padding: "10px 14px", background: "rgba(255,255,255,0.05)", border: "0.5px solid var(--b2)", borderRadius: 10, color: "var(--t1)", fontSize: 14, outline: "none", fontFamily: "inherit" };

    return React.createElement("div", { style: { padding: "24px 0", maxWidth: 640 } },
      item.file_url && React.createElement("div", { style: { marginBottom: 24, borderRadius: 10, overflow: "hidden", aspectRatio: "16/9", background: "var(--s2)" } },
        React.createElement("img", { src: item.file_url, style: { width: "100%", height: "100%", objectFit: "cover", display: "block" } })
      ),
      React.createElement("div", { style: { marginBottom: 18 } },
        React.createElement("label", { style: labelStyle }, "Title"),
        React.createElement("input", { style: inputStyle, value: form.title, placeholder: "Give your image a title", onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { title: e.target.value }); }); } })
      ),
      React.createElement("div", { style: { marginBottom: 18 } },
        React.createElement("label", { style: labelStyle }, "Description"),
        React.createElement("textarea", { style: Object.assign({}, inputStyle, { resize: "vertical", minHeight: 80 }), value: form.description, placeholder: "Optional description", rows: 3, onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { description: e.target.value }); }); } })
      ),
      tags.length > 0 && React.createElement("div", { style: { marginBottom: 24 } },
        React.createElement("label", { style: labelStyle }, "Tags"),
        React.createElement(TagSelector, { tags: tags, selectedIds: form.tag_ids, onChange: function (ids) { setForm(function (p) { return Object.assign({}, p, { tag_ids: ids }); }); }, maxTags: 5 })
      ),
      React.createElement("div", { style: { display: "flex", gap: 8 } },
        React.createElement("button", { className: "btn-primary", style: { fontSize: 13, padding: "8px 20px" }, onClick: function () { handleSave(false); }, disabled: saving }, saving ? "Publishing…" : "Publish"),
        React.createElement("button", { className: "btn-ghost",   style: { fontSize: 13, padding: "8px 16px" }, onClick: function () { handleSave(true);  }, disabled: saving }, "Save as draft"),
        React.createElement("button", { className: "btn-ghost",   style: { fontSize: 13, padding: "8px 16px", marginLeft: "auto" }, onClick: function () { NE.navigate("/ext/" + SLUG); }, disabled: saving }, "Discard")
      )
    );
  }

  // ─── CollectionCard ───────────────────────────────────────────────────────

  function CollectionCard(props) {
    var coll = props.collection;
    return React.createElement("div", {
      onClick: function () { NE.navigate("/ext/" + SLUG + "/collection/" + coll.slug); },
      style: {
        borderRadius: 10, overflow: "hidden", cursor: "pointer",
        background: "var(--s2)", border: "0.5px solid var(--b1)",
        transition: "border-color 0.15s",
      }
    },
      // Cover / placeholder
      React.createElement("div", {
        style: {
          position: "relative", aspectRatio: "16/9",
          background: coll.cover_url ? "var(--s3)" : "linear-gradient(135deg,var(--s3),var(--s2))",
          overflow: "hidden",
        }
      },
        coll.cover_url && React.createElement("img", {
          src: coll.cover_url, alt: coll.title,
          style: { width: "100%", height: "100%", objectFit: "cover" }
        }),
        !coll.cover_url && React.createElement("div", {
          style: { position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }
        },
          React.createElement("i", { className: "fa-solid fa-layer-group", style: { fontSize: 28, color: "var(--t5)" } })
        ),
        React.createElement("div", {
          style: {
            position: "absolute", bottom: 6, right: 8,
            background: "rgba(0,0,0,0.55)", borderRadius: 6,
            padding: "2px 8px", fontSize: 11.5, color: "#fff"
          }
        }, coll.item_count + " items")
      ),
      // Footer
      React.createElement("div", { style: { padding: "10px 12px" } },
        React.createElement("div", { style: { fontSize: 14, fontWeight: 500, color: "var(--t1)", marginBottom: 4, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } }, coll.title),
        coll.user && React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 6 } },
          React.createElement(Av, { user: coll.user, size: 18 }),
          React.createElement("span", { style: { fontSize: 12, color: "var(--t4)" } }, coll.user.username)
        )
      )
    );
  }

  // ─── NewCollectionModal ───────────────────────────────────────────────

  // Two-step modal: Step 1 = title/description, Step 2 = upload images into it.
  function NewCollectionModal(props) {
    var onClose   = props.onClose;
    var onCreated = props.onCreated;
    var maxSize   = props.maxCollectionSize || 100;

    // Step 1 fields
    var _title  = useState(""); var title  = _title[0];  var setTitle  = _title[1];
    var _desc   = useState(""); var desc   = _desc[0];   var setDesc   = _desc[1];
    var _saving = useState(false); var saving = _saving[0]; var setSaving = _saving[1];

    // Step 2 state
    var _step    = useState(1);   var step    = _step[0];    var setStep    = _step[1];
    var _coll    = useState(null);var coll    = _coll[0];    var setColl    = _coll[1];
    var _entries = useState([]);  var entries = _entries[0]; var setEntries = _entries[1];
    var inputRef = useRef(null);

    var allDone      = entries.length > 0 && entries.every(function (e) { return e.status === "done"; });
    var anyUploading = entries.some(function (e) { return e.status === "uploading" || e.status === "pending"; });
    var atMax        = entries.length >= maxSize;

    // Step 1 — create collection
    function handleCreate() {
      if (!title.trim()) return;
      setSaving(true);
      apiPost("/collections", { title: title.trim(), description: desc.trim() || null })
        .then(function (d) {
          if (d.collection) {
            setColl(d.collection);
            setStep(2);
          } else {
            toast(d.error || "Failed to create", "err");
          }
        })
        .catch(function () { toast("Failed to create collection", "err"); })
        .finally(function () { setSaving(false); });
    }

    // Step 2 — upload images and add to collection
    function handleFiles(files) {
      var arr = Array.from(files).filter(function (f) {
        return f.type.startsWith("image/");
      });
      var available = maxSize - entries.length;
      arr = arr.slice(0, available);
      if (!arr.length) return;
      var idx0 = entries.length;
      var newEntries = arr.map(function (f) {
        return { file: f, previewUrl: URL.createObjectURL(f), status: "pending", progress: 0 };
      });
      setEntries(function (prev) { return prev.concat(newEntries); });
      newEntries.forEach(function (entry, i) { startUpload(idx0 + i, entry); });
    }

    function startUpload(idx, entry) {
      apiPost("/items/draft", { media_type: "image" })
        .then(function (d) {
          if (!d.id) throw new Error(d.error || "Failed to create draft");
          var draftId = d.id;
          setEntries(function (prev) {
            var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { status: "uploading", draftId: draftId }); return u;
          });
          return uploadFileXhr(entry.file, draftId, function (pct) {
            setEntries(function (prev) {
              var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { progress: pct }); return u;
            });
          }).then(function (r) {
            return apiPatch("/items/" + draftId, {
              file_url:     r.url,
              original_url: r.original_url,
              upload_id:    r.upload ? r.upload.id : null,
            }).then(function () {
              return apiPost("/collections/" + coll.slug + "/items", { item_id: draftId })
                .then(function () {
                  setEntries(function (prev) {
                    var u = prev.slice();
                    u[idx] = Object.assign({}, u[idx], { status: "done", progress: 100, url: r.url });
                    return u;
                  });
                });
            });
          });
        })
        .catch(function (err) {
          setEntries(function (prev) {
            var u = prev.slice(); u[idx] = Object.assign({}, u[idx], { status: "error", progress: 0, error: err.message }); return u;
          });
          toast(err.message || "Upload failed", "err");
        });
    }

    function handleDrop(e) { e.preventDefault(); if (e.dataTransfer.files.length) handleFiles(e.dataTransfer.files); }

    function handleFinish() {
      onCreated(coll);
    }

    return React.createElement("div", {
      style: {
        position: "fixed", inset: 0, zIndex: 1000,
        background: "rgba(0,0,0,0.6)", backdropFilter: "blur(4px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: 16,
      },
      onClick: function (e) { if (e.target === e.currentTarget && !anyUploading) onClose(); }
    },
      React.createElement("div", {
        style: {
          background: "var(--s1)", borderRadius: 14, padding: 24,
          width: "100%", maxWidth: 520, border: "0.5px solid var(--b2)",
          display: "flex", flexDirection: "column", gap: 0,
        }
      },
        // Header
        React.createElement("div", {
          style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }
        },
          React.createElement("span", { style: { fontSize: 16, fontWeight: 600, color: "var(--t1)" } },
            step === 1 ? "New collection" : "Add images — " + coll.title
          ),
          React.createElement("button", {
            onClick: step === 1 ? onClose : handleFinish,
            disabled: anyUploading,
            style: { background: "none", border: "none", color: "var(--t4)", cursor: "pointer", fontSize: 18, lineHeight: 1 }
          }, React.createElement("i", { className: step === 1 ? "fa-solid fa-xmark" : "fa-solid fa-check" }))
        ),

        // Step 1 — collection details
        step === 1 && React.createElement("div", null,
          React.createElement("div", { style: { marginBottom: 14 } },
            React.createElement("label", { style: { fontSize: 12.5, color: "var(--t3)", display: "block", marginBottom: 6 } }, "Title *"),
            React.createElement("input", {
              className: "fi", placeholder: "My collection",
              value: title, autoFocus: true,
              onChange: function (e) { setTitle(e.target.value); },
              onKeyDown: function (e) { if (e.key === "Enter") handleCreate(); },
            })
          ),
          React.createElement("div", { style: { marginBottom: 20 } },
            React.createElement("label", { style: { fontSize: 12.5, color: "var(--t3)", display: "block", marginBottom: 6 } }, "Description"),
            React.createElement("textarea", {
              className: "fi", placeholder: "Optional…",
              rows: 3, value: desc,
              style: { resize: "vertical" },
              onChange: function (e) { setDesc(e.target.value); },
            })
          ),
          React.createElement("div", { style: { display: "flex", gap: 8, justifyContent: "flex-end" } },
            React.createElement("button", { className: "btn-ghost", onClick: onClose, disabled: saving }, "Cancel"),
            React.createElement("button", {
              className: "btn-primary", onClick: handleCreate,
              disabled: saving || !title.trim(),
            }, saving ? "Creating…" : "Next →")
          )
        ),

        // Step 2 — image uploads
        step === 2 && React.createElement("div", null,
          // Drop zone (only when no entries yet)
          entries.length === 0 && React.createElement("div", {
            style: {
              border: "1.5px dashed var(--b2)", borderRadius: 10,
              padding: "28px 24px", textAlign: "center",
              cursor: "pointer", color: "var(--t4)", fontSize: 13,
              marginBottom: 16,
            },
            onClick: function () { inputRef.current && inputRef.current.click(); },
            onDrop: handleDrop,
            onDragOver: function (e) { e.preventDefault(); },
          },
            React.createElement("i", { className: "fa-solid fa-upload", style: { fontSize: 26, display: "block", marginBottom: 10, color: "var(--t5)" } }),
            React.createElement("div", null, "Click to add images or drag and drop"),
            React.createElement("div", { style: { fontSize: 11, color: "var(--t5)", marginTop: 4 } }, "JPEG, PNG, GIF, WebP · up to " + maxSize + " images")
          ),

          // Thumbnail grid with grayscale/color progress reveal
          entries.length > 0 && React.createElement("div", {
            style: {
              display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
              gap: 8, overflowY: "auto", maxHeight: 260, marginBottom: 16,
            }
          },
            entries.map(function (entry, i) {
              var clip = entry.status === "done" ? 0 : 100 - (entry.progress || 0);
              return React.createElement("div", {
                key: i,
                style: { position: "relative", aspectRatio: "1/1", borderRadius: 6, overflow: "hidden", background: "var(--s3)" }
              },
                // Grayscale base layer
                React.createElement("img", {
                  src: entry.previewUrl,
                  style: { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", filter: "grayscale(1)" }
                }),
                // Color layer revealed top-down as progress increases
                React.createElement("img", {
                  src: entry.previewUrl,
                  style: {
                    position: "absolute", inset: 0, width: "100%", height: "100%",
                    objectFit: "cover",
                    clipPath: "inset(" + clip + "% 0 0 0)",
                    transition: "clip-path 0.1s linear",
                  }
                }),
                entry.status === "error" && React.createElement("div", {
                  style: {
                    position: "absolute", inset: 0,
                    background: "rgba(248,113,113,0.75)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 11, color: "#fff", padding: 4, textAlign: "center",
                  }
                }, entry.error || "Failed")
              );
            }),
            // Add more tile
            !atMax && React.createElement("div", {
              style: {
                aspectRatio: "1/1", borderRadius: 6,
                border: "1.5px dashed var(--b2)",
                display: "flex", alignItems: "center", justifyContent: "center",
                cursor: "pointer", color: "var(--t5)", fontSize: 22,
              },
              onClick: function () { inputRef.current && inputRef.current.click(); }
            }, React.createElement("i", { className: "fa-solid fa-plus" }))
          ),

          React.createElement("div", { style: { display: "flex", gap: 8, justifyContent: "flex-end" } },
            React.createElement("button", {
              className: "btn-ghost", onClick: handleFinish,
              disabled: anyUploading,
            }, entries.length === 0 ? "Skip" : anyUploading ? "Uploading…" : "Done"),
            entries.length === 0 && React.createElement("button", {
              className: "btn-primary",
              onClick: function () { inputRef.current && inputRef.current.click(); },
            },
              React.createElement("i", { className: "fa-solid fa-upload", style: { marginRight: 6 } }),
              "Upload images"
            )
          )
        ),

        React.createElement("input", {
          ref: inputRef,
          type: "file",
          accept: "image/jpeg,image/png,image/gif,image/webp",
          multiple: true,
          style: { display: "none" },
          onChange: function (e) { if (e.target.files.length) handleFiles(e.target.files); e.target.value = ""; }
        })
      )
    );
  }

  // ─── AddToCollectionModal ─────────────────────────────────────────────────

  function AddToCollectionModal(props) {
    var itemId  = props.itemId;
    var onClose = props.onClose;
    var _colls   = useState(null); var colls   = _colls[0];   var setColls   = _colls[1];
    var _inColls = useState([]);   var inColls  = _inColls[0]; var setInColls = _inColls[1];
    var _busy    = useState({});   var busy     = _busy[0];    var setBusy    = _busy[1];

    useEffect(function () {
      Promise.all([
        apiGet("/my-collections"),
        apiGet("/items/" + itemId + "/collections"),
      ]).then(function (results) {
        setColls(results[0].collections || []);
        setInColls((results[1].collections || []).map(function (c) { return c.slug; }));
      }).catch(function () { setColls([]); });
    }, [itemId]);

    function toggle(slug) {
      var isIn = inColls.indexOf(slug) >= 0;
      setBusy(function (b) { return Object.assign({}, b, { [slug]: true }); });
      var req = isIn
        ? apiDelete("/collections/" + slug + "/items/" + itemId)
        : apiPost("/collections/" + slug + "/items", { item_id: itemId });
      req.then(function (d) {
        if (d.ok || d.item_count !== undefined) {
          setInColls(function (prev) {
            return isIn ? prev.filter(function (s) { return s !== slug; }) : prev.concat([slug]);
          });
        } else {
          toast(d.error || "Failed", "err");
        }
      })
      .catch(function () { toast("Failed", "err"); })
      .finally(function () {
        setBusy(function (b) { var n = Object.assign({}, b); delete n[slug]; return n; });
      });
    }

    return React.createElement("div", {
      style: {
        position: "fixed", inset: 0, zIndex: 1000,
        background: "rgba(0,0,0,0.6)", backdropFilter: "blur(4px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: 16,
      },
      onClick: function (e) { if (e.target === e.currentTarget) onClose(); }
    },
      React.createElement("div", {
        style: {
          background: "var(--s1)", borderRadius: 14, padding: 24,
          width: "100%", maxWidth: 420, border: "0.5px solid var(--b2)",
          maxHeight: "70vh", display: "flex", flexDirection: "column",
        }
      },
        React.createElement("div", {
          style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 }
        },
          React.createElement("span", { style: { fontSize: 15, fontWeight: 600, color: "var(--t1)" } }, "Add to collection"),
          React.createElement("button", {
            onClick: onClose,
            style: { background: "none", border: "none", color: "var(--t4)", cursor: "pointer", fontSize: 18, lineHeight: 1 }
          }, React.createElement("i", { className: "fa-solid fa-xmark" }))
        ),
        colls === null
          ? React.createElement("div", { style: { textAlign: "center", padding: "24px 0", color: "var(--t5)" } },
              React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }))
          : colls.length === 0
            ? React.createElement("div", { style: { textAlign: "center", padding: "24px 0", color: "var(--t5)", fontSize: 13 } },
                "You have no collections yet.")
            : React.createElement("div", { style: { overflowY: "auto", display: "flex", flexDirection: "column", gap: 6 } },
                colls.map(function (coll) {
                  var isIn = inColls.indexOf(coll.slug) >= 0;
                  var loading = !!busy[coll.slug];
                  return React.createElement("div", {
                    key: coll.slug,
                    style: {
                      display: "flex", alignItems: "center", justifyContent: "space-between",
                      padding: "10px 12px", borderRadius: 8,
                      background: isIn ? "var(--ac-bg)" : "var(--s2)",
                      border: "0.5px solid " + (isIn ? "var(--ac-border)" : "var(--b1)"),
                    }
                  },
                    React.createElement("div", null,
                      React.createElement("div", { style: { fontSize: 13.5, fontWeight: 500, color: "var(--t1)" } }, coll.title),
                      React.createElement("div", { style: { fontSize: 11.5, color: "var(--t5)" } }, coll.item_count + " items")
                    ),
                    React.createElement("button", {
                      onClick: function () { toggle(coll.slug); },
                      disabled: loading,
                      style: {
                        padding: "5px 12px", borderRadius: 6, fontSize: 12,
                        border: "0.5px solid " + (isIn ? "var(--ac-border)" : "var(--b2)"),
                        background: isIn ? "var(--ac-bg)" : "transparent",
                        color: isIn ? "var(--ac-text)" : "var(--t3)",
                        cursor: "pointer", fontFamily: "inherit",
                      }
                    }, loading ? React.createElement("i", { className: "fa-solid fa-spinner fa-spin" })
                                : isIn ? "Remove" : "Add")
                  );
                })
              )
      )
    );
  }


  // ─── Placeholder routes ───────────────────────────────────────────────────

  function Placeholder(props) {
    return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t4)", fontSize: 14 } },
      React.createElement("i", { className: "fa-solid fa-images", style: { fontSize: 32, display: "block", marginBottom: 16, color: "var(--t5)" } }),
      React.createElement("div", { style: { fontWeight: 500, color: "var(--t2)", marginBottom: 8 } }, props.title || "Gallery"),
      React.createElement("div", null, "Coming in a future phase.")
    );
  }

  // ─── Star rating component ────────────────────────────────────────────────

  function StarRating(props) {
    var value    = props.value;      // current user rating 1-5 or null
    var avg      = props.avg;        // float or null
    var count    = props.count || 0;
    var onRate   = props.onRate;     // function(value) — null if readonly
    var _hover   = useState(0); var hover = _hover[0]; var setHover = _hover[1];

    var stars = [1, 2, 3, 4, 5];
    var display = hover || value || 0;
    var canRate = typeof onRate === "function";

    return React.createElement("div", {
      style: { display: "flex", alignItems: "center", gap: 6 }
    },
      // Stars
      React.createElement("div", {
        style: { display: "flex", gap: 2 },
        onMouseLeave: canRate ? function () { setHover(0); } : null,
      },
        stars.map(function (n) {
          var filled = n <= display;
          return React.createElement("i", {
            key: n,
            className: filled ? "fa-solid fa-star" : "fa-regular fa-star",
            style: {
              fontSize: 16,
              color: filled ? "#fbbf24" : "var(--t5)",
              cursor: canRate ? "pointer" : "default",
              transition: "color 0.1s",
            },
            onMouseEnter: canRate ? function () { setHover(n); } : null,
            onClick: canRate ? function () {
              // Clicking the current value clears the rating
              onRate(n === value ? null : n);
            } : null,
          });
        })
      ),
      // Stats
      avg != null && React.createElement("span", {
        style: { fontSize: 12.5, color: "var(--t4)" }
      },
        avg.toFixed(1) + " (" + count + ")"
      ),
      count === 0 && avg == null && React.createElement("span", {
        style: { fontSize: 12.5, color: "var(--t5)" }
      }, canRate ? "Be the first to rate" : "No ratings yet")
    );
  }

  // ─── Reaction strip ───────────────────────────────────────────────────────

  var REACTIONS = [
    { emoji: "\u2764\ufe0f", icon: "fa-solid fa-heart",         color: "#f87171" },
    { emoji: "\ud83d\udc4d", icon: "fa-solid fa-thumbs-up",     color: "#60a5fa" },
    { emoji: "\ud83d\ude02", icon: "fa-solid fa-face-laugh",    color: "#fbbf24" },
    { emoji: "\ud83d\ude2e", icon: "fa-solid fa-face-surprise", color: "#a78bfa" },
    { emoji: "\ud83d\udd25", icon: "fa-solid fa-fire",          color: "#fb923c" },
    { emoji: "\ud83d\udc4f", icon: "fa-solid fa-hands-clapping", color: "#34d399" },
  ];

  function ReactionStrip(props) {
    var counts  = props.counts || {};
    var mine    = props.mine   || [];
    var onReact = props.onReact; // function(emoji) — null if readonly
    var canReact = typeof onReact === "function";

    return React.createElement("div", {
      style: { display: "flex", flexWrap: "wrap", gap: 6 }
    },
      REACTIONS.map(function (r) {
        var count  = counts[r.emoji] || 0;
        var active = mine.indexOf(r.emoji) >= 0;
        return React.createElement("button", {
          key: r.emoji,
          onClick: canReact ? function () { onReact(r.emoji); } : null,
          disabled: !canReact,
          style: {
            display:     "inline-flex",
            alignItems:  "center",
            gap:         5,
            padding:     "4px 10px",
            borderRadius: 20,
            border:      "0.5px solid " + (active ? r.color + "88" : "var(--b2)"),
            background:  active ? r.color + "18" : "transparent",
            color:       active ? r.color : "var(--t4)",
            fontSize:    13,
            cursor:      canReact ? "pointer" : "default",
            fontFamily:  "inherit",
            transition:  "all 0.1s",
          }
        },
          React.createElement("i", {
            className: r.icon,
            style: { fontSize: 13, color: active ? r.color : "var(--t5)" }
          }),
          count > 0 && React.createElement("span", {
            style: { fontSize: 12, fontWeight: active ? 500 : 400 }
          }, count)
        );
      })
    );
  }


  // ─── YouTube ID extractor ─────────────────────────────────────────────────

  function extractYouTubeId(url) {
    if (!url) return null;
    var m = url.match(/(?:youtu\.be\/|v=|embed\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
  }

  // ─── Gallery item detail page ─────────────────────────────────────────────

  function GalleryItemPage(props) {
    var uuid        = props.uuid;
    var currentUser = props.currentUser;

    var _item     = useState(null);  var item     = _item[0];     var setItem     = _item[1];
    var _allTags  = useState([]);    var allTags  = _allTags[0];  var setAllTags  = _allTags[1];
    var _loading  = useState(true);  var loading  = _loading[0];  var setLoading  = _loading[1];
    var _editing  = useState(false); var editing  = _editing[0];  var setEditing  = _editing[1];
    var _saving   = useState(false); var saving   = _saving[0];   var setSaving   = _saving[1];
    var _form     = useState({ title: "", description: "", tag_ids: [] });
    var form = _form[0]; var setForm = _form[1];
    var _rating   = useState({ my_rating: null, avg: null, count: 0 });
    var rating    = _rating[0];    var setRating   = _rating[1];
    var _reactions = useState({ counts: {}, mine: [] });
    var reactions  = _reactions[0]; var setReactions = _reactions[1];
    var _perms    = useState({});   var perms      = _perms[0];    var setPerms    = _perms[1];
    var _comments     = useState([]);   var comments     = _comments[0];     var setComments     = _comments[1];
    var _commentTotal = useState(0);    var commentTotal = _commentTotal[0]; var setCommentTotal = _commentTotal[1];
    var _commentPage  = useState(1);    var commentPage  = _commentPage[0];  var setCommentPage  = _commentPage[1];
    var _commentBody  = useState("");   var commentBody  = _commentBody[0];  var setCommentBody  = _commentBody[1];
    var _commenting         = useState(false); var commenting         = _commenting[0];         var setCommenting         = _commenting[1];
    var _showAddToCollection = useState(false); var showAddToCollection = _showAddToCollection[0]; var setShowAddToCollection = _showAddToCollection[1];

    useEffect(function () {
      Promise.all([
        apiGet("/items/" + uuid),
        apiGet("/tags/public"),
        apiGet("/items/" + uuid + "/ratings"),
        apiGet("/items/" + uuid + "/reactions"),
        apiGet("/permissions"),
        apiGet("/items/" + uuid + "/comments?page=1"),
      ]).then(function (results) {
        if (results[0].item) {
          var i = results[0].item;
          setItem(i);
          setForm({
            title:       i.title || "",
            description: i.description || "",
            tag_ids:     (i.tags || []).map(function (t) { return t.id; }),
          });
        }
        if (results[1].tags) setAllTags(results[1].tags);
        if (results[2] && typeof results[2].count === "number") setRating(results[2]);
        if (results[3] && results[3].counts) setReactions(results[3]);
        if (results[4] && results[4].permissions) setPerms(results[4]);
        if (results[5] && results[5].comments) {
          setComments(results[5].comments);
          setCommentTotal(results[5].total || 0);
        }
        setLoading(false);
      }).catch(function () { setLoading(false); });
    }, [uuid]);

    function handleSave() {
      setSaving(true);
      apiPatch("/items/" + uuid, form)
        .then(function (d) {
          if (d.item) {
            setItem(d.item);
            setEditing(false);
            toast("Saved");
          } else {
            toast(d.error || "Save failed", "err");
          }
        })
        .catch(function () { toast("Save failed", "err"); })
        .finally(function () { setSaving(false); });
    }

    function handleFeature() {
      apiPost("/items/" + uuid + "/feature")
        .then(function (d) {
          if (typeof d.is_featured === "boolean") {
            setItem(function (prev) { return Object.assign({}, prev, { is_featured: d.is_featured }); });
            toast(d.is_featured ? "Marked as featured" : "Removed from featured");
          } else {
            toast(d.error || "Failed", "err");
          }
        })
        .catch(function () { toast("Failed", "err"); });
    }

    function handleDelete() {
      if (!window.confirm("Delete this item? This cannot be undone.")) return;
      apiDelete("/items/" + uuid)
        .then(function (d) {
          if (d.ok) {
            toast("Deleted");
            NE.navigate("/ext/" + SLUG);
          } else {
            toast(d.error || "Delete failed", "err");
          }
        })
        .catch(function () { toast("Delete failed", "err"); });
    }

    function handleRate(value) {
      if (value === null) {
        apiDelete("/items/" + uuid + "/ratings")
          .then(function (d) {
            if (typeof d.count === "number") setRating(d);
          })
          .catch(function () { toast("Failed to remove rating", "err"); });
      } else {
        apiPost("/items/" + uuid + "/ratings", { value: value })
          .then(function (d) {
            if (typeof d.count === "number") setRating(d);
          })
          .catch(function () { toast("Failed to rate", "err"); });
      }
    }

    function handleReact(emoji) {
      apiPost("/items/" + uuid + "/reactions", { emoji: emoji })
        .then(function (d) {
          if (d.counts) setReactions(d);
        })
        .catch(function () { toast("Failed to react", "err"); });
    }

    function loadComments(page) {
      apiGet("/items/" + uuid + "/comments?page=" + page)
        .then(function (d) {
          if (d.comments) {
            setComments(d.comments);
            setCommentTotal(d.total || 0);
            setCommentPage(page);
          }
        })
        .catch(function () {});
    }

    function handleComment() {
      if (!commentBody.trim()) return;
      setCommenting(true);
      apiPost("/items/" + uuid + "/comments", { body: commentBody })
        .then(function (d) {
          if (d.comment) {
            setComments(function (prev) { return prev.concat([d.comment]); });
            setCommentTotal(function (n) { return n + 1; });
            setCommentBody("");
          } else {
            toast(d.error || "Failed to post comment", "err");
          }
        })
        .catch(function () { toast("Failed to post comment", "err"); })
        .finally(function () { setCommenting(false); });
    }

    function handleDeleteComment(commentId) {
      if (!window.confirm("Delete this comment?")) return;
      apiDelete("/items/" + uuid + "/comments/" + commentId)
        .then(function (d) {
          if (d.ok) {
            setComments(function (prev) { return prev.filter(function (c) { return c.id !== commentId; }); });
            setCommentTotal(function (n) { return n - 1; });
          } else {
            toast(d.error || "Failed to delete", "err");
          }
        })
        .catch(function () { toast("Failed to delete", "err"); });
    }

    function handleOpenLightbox() {
      if (!item || item.media_type !== "image") return;
      window._openFancybox([{
        src:         item.file_url,
        originalSrc: item.original_url || item.file_url,
      }], 0);
    }

    function toggleTag(tagId) {
      setForm(function (p) {
        var ids = p.tag_ids.indexOf(tagId) >= 0
          ? p.tag_ids.filter(function (x) { return x !== tagId; })
          : p.tag_ids.concat([tagId]);
        return Object.assign({}, p, { tag_ids: ids });
      });
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

    var ytId = item.media_type === "embed" ? extractYouTubeId(item.embed_url) : null;

    return React.createElement("div", { style: { paddingBottom: 40 } },

      // Back button
      React.createElement("button", {
        className: "btn-ghost",
        style: { fontSize: 12.5, marginBottom: 16, display: "inline-flex", alignItems: "center", gap: 6 },
        onClick: function () { NE.navigate("/ext/" + SLUG); },
      },
        React.createElement("i", { className: "fa-solid fa-arrow-left", style: { fontSize: 11 } }),
        " Gallery"
      ),

      // ── Media display ──────────────────────────────────────────────────────

      // Image
      item.media_type === "image" && item.file_url &&
        React.createElement("div", {
          onClick: handleOpenLightbox,
          style: {
            width: "100%", aspectRatio: "16/9",
            borderRadius: 10, overflow: "hidden",
            background: "var(--s2)", cursor: "zoom-in",
            border: "0.5px solid var(--b1)", marginBottom: 16,
          }
        },
          React.createElement("img", {
            src: item.file_url,
            style: { width: "100%", height: "100%", objectFit: "cover", display: "block" },
            loading: "lazy",
          })
        ),

      // Video
      item.media_type === "video" && item.file_url &&
        React.createElement("div", {
          style: {
            width: "100%", aspectRatio: "16/9",
            borderRadius: 10, overflow: "hidden",
            background: "#000", border: "0.5px solid var(--b1)", marginBottom: 16,
          }
        },
          React.createElement("video", {
            src: item.file_url,
            controls: true,
            style: { width: "100%", height: "100%", display: "block" },
          })
        ),

      // YouTube embed — uses Nexus's existing document click handler on .yt-lite
      item.media_type === "embed" && ytId &&
        React.createElement("div", {
          className: "yt-lite",
          "data-id": ytId,
          style: { marginBottom: 16 },
        },
          React.createElement("img", {
            className: "yt-thumb",
            src: "https://i.ytimg.com/vi/" + ytId + "/maxresdefault.jpg",
            alt: item.title || "YouTube video",
            loading: "lazy",
            onError: function (e) {
              e.target.src = "https://i.ytimg.com/vi/" + ytId + "/hqdefault.jpg";
            },
          }),
          React.createElement("div", { className: "yt-play" },
            React.createElement("svg", { viewBox: "0 0 68 48", width: "68", height: "48" },
              React.createElement("path", {
                d: "M66.52 7.74c-.78-2.93-2.49-5.41-5.42-6.19C55.79.13 34 0 34 0S12.21.13 6.9 1.55c-2.93.78-4.63 3.26-5.42 6.19C.06 13.05 0 24 0 24s.06 10.95 1.48 16.26c.78 2.93 2.49 5.41 5.42 6.19C12.21 47.87 34 48 34 48s21.79-.13 27.1-1.55c2.93-.78 4.64-3.26 5.42-6.19C67.94 34.95 68 24 68 24s-.06-10.95-1.48-16.26z",
                fill: "#f00",
              }),
              React.createElement("path", { d: "M45 24 27 14v20", fill: "#fff" })
            )
          )
        ),

      // ── Title, uploader, actions ───────────────────────────────────────────

      React.createElement("div", {
        style: { display: "flex", alignItems: "flex-start", gap: 12, marginBottom: 10 }
      },
        // Left: title + uploader
        React.createElement("div", { style: { flex: 1, minWidth: 0 } },
          React.createElement("h1", {
            style: { fontSize: 20, fontWeight: 500, color: "var(--t1)", margin: "0 0 8px 0" }
          }, item.title || React.createElement("span", { style: { color: "var(--t5)" } }, "Untitled")),
          item.user && React.createElement("div", {
            style: { display: "flex", alignItems: "center", gap: 7, fontSize: 12.5, color: "var(--t4)" }
          },
            React.createElement(Av, { user: item.user, size: 20 }),
            React.createElement("span", null, item.user.username),
            React.createElement("span", null, "·"),
            item.inserted_at && React.createElement("span", null,
              new Date(item.inserted_at).toLocaleDateString()
            ),
            React.createElement("span", null, "·"),
            React.createElement("i", { className: "fa-solid fa-eye", style: { fontSize: 10 } }),
            React.createElement("span", null, " " + (item.view_count || 0))
          )
        ),
        // Right: action buttons
        React.createElement("div", { style: { display: "flex", gap: 6, flexShrink: 0, flexWrap: "wrap", justifyContent: "flex-end" } },
          item.can_feature && React.createElement("button", {
            className: "btn-ghost",
            style: {
              fontSize: 12, padding: "5px 12px",
              color: item.is_featured ? "#fbbf24" : "var(--t4)",
              borderColor: item.is_featured ? "rgba(251,191,36,0.4)" : undefined,
            },
            onClick: handleFeature,
          },
            React.createElement("i", { className: "fa-solid fa-star", style: { marginRight: 5 } }),
            item.is_featured ? "Unfeature" : "Feature"
          ),
          item.can_edit && !editing && React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 12, padding: "5px 12px" },
            onClick: function () { setEditing(true); },
          },
            React.createElement("i", { className: "fa-solid fa-pen", style: { marginRight: 5 } }),
            "Edit"
          ),
          item.can_delete && React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 12, padding: "5px 12px", color: "var(--red)", borderColor: "rgba(248,113,113,0.3)" },
            onClick: handleDelete,
          },
            React.createElement("i", { className: "fa-solid fa-trash", style: { marginRight: 5 } }),
            "Delete"
          ),
          currentUser && React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 12, padding: "5px 12px" },
            onClick: function () { setShowAddToCollection(true); },
          },
            React.createElement("i", { className: "fa-solid fa-layer-group", style: { marginRight: 5 } }),
            "Collect"
          )
        )
      ),

      showAddToCollection && React.createElement(AddToCollectionModal, {
        itemId:  uuid,
        onClose: function () { setShowAddToCollection(false); },
      }),

      // Featured badge
      item.is_featured && React.createElement("div", {
        style: {
          display: "inline-flex", alignItems: "center", gap: 5, marginBottom: 10,
          background: "rgba(251,191,36,0.12)", color: "#fbbf24",
          fontSize: 11.5, padding: "2px 10px", borderRadius: 20,
          border: "0.5px solid rgba(251,191,36,0.3)",
        }
      },
        React.createElement("i", { className: "fa-solid fa-star", style: { fontSize: 10 } }),
        " Featured"
      ),

      // Tags (view mode)
      !editing && item.tags && item.tags.length > 0 &&
        React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14 } },
          item.tags.map(function (tag) {
            return React.createElement("div", {
              key: tag.id,
              onClick: function () { NE.navigate("/ext/" + SLUG + "?tag=" + tag.slug); },
              style: {
                display: "inline-flex", alignItems: "center", gap: 5,
                padding: "3px 10px", borderRadius: 20, cursor: "pointer",
                border: "0.5px solid " + tag.color + "55",
                background: tag.color + "18", color: tag.color, fontSize: 12,
              }
            },
              React.createElement("div", {
                style: { width: 6, height: 6, borderRadius: "50%", background: tag.color, flexShrink: 0 }
              }),
              tag.name
            );
          })
        ),

      // Description (view mode)
      !editing && item.description &&
        React.createElement("div", { style: { marginBottom: 16 } },
          React.createElement(Md, { text: item.description })
        ),


      // ── Ratings and reactions ────────────────────────────

      !editing && (perms.ratings_enabled === true) && React.createElement("div", {
        style: { marginBottom: 16 }
      },
        React.createElement(StarRating, {
          value:  rating.my_rating,
          avg:    rating.avg,
          count:  rating.count,
          onRate: (perms.permissions && perms.permissions.can_rate &&
                   !(perms.block_self_ratings && item && currentUser && item.user_id === currentUser.id))
                   ? handleRate : null,
        })
      ),

      !editing && (perms.reactions_enabled === true) && React.createElement("div", {
        style: { marginBottom: 20 }
      },
        React.createElement(ReactionStrip, {
          counts:  reactions.counts,
          mine:    reactions.mine,
          onReact: (perms.permissions && perms.permissions.can_react &&
                    !(perms.block_self_reactions && item && currentUser && item.user_id === currentUser.id))
                    ? handleReact : null,
        })
      ),

      // ── Comments ──────────────────────────────────────────────────────────────

      !editing && (perms.comments_enabled === true) && React.createElement("div", {
        style: { marginTop: 24, paddingTop: 20, borderTop: "0.5px solid var(--b1)" }
      },
        // Section header
        React.createElement("div", {
          style: { fontSize: 13, fontWeight: 500, color: "var(--t3)", marginBottom: 16 }
        },
          React.createElement("i", { className: "fa-solid fa-comment", style: { marginRight: 7, fontSize: 12 } }),
          commentTotal + (commentTotal === 1 ? " comment" : " comments")
        ),

        // Comment input — only for users with can_comment permission
        perms.permissions && perms.permissions.can_comment && React.createElement("div", {
          style: { display: "flex", gap: 10, marginBottom: 20, alignItems: "flex-start" }
        },
          currentUser && React.createElement(Av, { user: currentUser, size: 28 }),
          React.createElement("div", { style: { flex: 1 } },
            React.createElement("textarea", {
              value: commentBody,
              placeholder: "Write a comment…",
              rows: 3,
              style: {
                width: "100%", padding: "10px 14px",
                background: "rgba(255,255,255,0.05)",
                border: "0.5px solid var(--b2)",
                borderRadius: 10, color: "var(--t1)",
                fontSize: 14, outline: "none",
                fontFamily: "inherit", resize: "vertical",
                minHeight: 70,
              },
              onChange: function (e) { setCommentBody(e.target.value); },
              onKeyDown: function (e) {
                // Ctrl+Enter or Cmd+Enter submits
                if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
                  e.preventDefault();
                  handleComment();
                }
              },
            }),
            React.createElement("div", { style: { display: "flex", justifyContent: "flex-end", marginTop: 6 } },
              React.createElement("button", {
                className: "btn-primary",
                style: { fontSize: 12.5, padding: "6px 14px" },
                onClick: handleComment,
                disabled: commenting || !commentBody.trim(),
              }, commenting ? "Posting…" : "Post comment")
            )
          )
        ),

        // Comment list
        comments.length === 0 && React.createElement("div", {
          style: { fontSize: 13, color: "var(--t5)", padding: "12px 0" }
        }, "No comments yet. Be the first!"),

        React.createElement("div", { style: { display: "flex", flexDirection: "column", gap: 14 } },
          comments.map(function (c) {
            return React.createElement("div", {
              key: c.id,
              style: {
                display: "flex", gap: 10, alignItems: "flex-start",
                padding: "12px 14px",
                background: "var(--s2)",
                borderRadius: 10,
                border: "0.5px solid var(--b1)",
              }
            },
              c.user && React.createElement(Av, { user: c.user, size: 28 }),
              React.createElement("div", { style: { flex: 1, minWidth: 0 } },
                React.createElement("div", {
                  style: { display: "flex", alignItems: "center", gap: 8, marginBottom: 5 }
                },
                  c.user && React.createElement("span", {
                    style: { fontSize: 13, fontWeight: 500, color: "var(--t2)" }
                  }, c.user.username),
                  React.createElement("span", {
                    style: { fontSize: 11.5, color: "var(--t5)" }
                  }, c.inserted_at ? new Date(c.inserted_at).toLocaleDateString() : ""),
                  c.can_delete && React.createElement("button", {
                    onClick: function () { handleDeleteComment(c.id); },
                    style: {
                      marginLeft: "auto", background: "none", border: "none",
                      color: "var(--t5)", cursor: "pointer", fontSize: 11,
                      padding: "2px 6px", borderRadius: 4,
                    }
                  }, React.createElement("i", { className: "fa-solid fa-trash" }))
                ),
                React.createElement(Md, { text: c.body })
              )
            );
          })
        ),

        // Pagination
        commentTotal > 20 && React.createElement("div", {
          style: { display: "flex", justifyContent: "center", gap: 6, marginTop: 16 }
        },
          commentPage > 1 && React.createElement("button", {
            className: "btn-ghost", style: { fontSize: 12 },
            onClick: function () { loadComments(commentPage - 1); }
          }, React.createElement("i", { className: "fa-solid fa-chevron-left" })),
          React.createElement("span", {
            style: { fontSize: 12.5, color: "var(--t4)", padding: "6px 10px" }
          }, "Page " + commentPage + " of " + Math.ceil(commentTotal / 20)),
          commentPage < Math.ceil(commentTotal / 20) && React.createElement("button", {
            className: "btn-ghost", style: { fontSize: 12 },
            onClick: function () { loadComments(commentPage + 1); }
          }, React.createElement("i", { className: "fa-solid fa-chevron-right" }))
        )
      ),

      // ── Edit form (inline) ─────────────────────────────────────────────────

      editing && React.createElement("div", {
        style: {
          background: "var(--s2)", border: "0.5px solid var(--b2)",
          borderRadius: 12, padding: "18px 20px", marginBottom: 16,
        }
      },
        React.createElement("div", { className: "fg" },
          React.createElement("label", { className: "fl" }, "Title"),
          React.createElement("input", {
            className: "fi",
            value: form.title,
            placeholder: "Title",
            onChange: function (e) {
              setForm(function (p) { return Object.assign({}, p, { title: e.target.value }); });
            },
          })
        ),
        React.createElement("div", { className: "fg" },
          React.createElement("label", { className: "fl" }, "Description"),
          React.createElement("textarea", {
            className: "fi",
            rows: 4,
            value: form.description,
            placeholder: "Optional description",
            style: { resize: "vertical", minHeight: 80 },
            onChange: function (e) {
              setForm(function (p) { return Object.assign({}, p, { description: e.target.value }); });
            },
          })
        ),
        allTags.length > 0 && React.createElement("div", { className: "fg" },
          React.createElement("label", { className: "fl" }, "Tags"),
          React.createElement("div", { style: { display: "flex", flexWrap: "wrap", gap: 6 } },
            allTags.map(function (tag) {
              var sel = form.tag_ids.indexOf(tag.id) >= 0;
              return React.createElement("div", {
                key: tag.id,
                onClick: function () { toggleTag(tag.id); },
                style: {
                  display: "inline-flex", alignItems: "center", gap: 5,
                  padding: "3px 10px", borderRadius: 20, cursor: "pointer",
                  border: "0.5px solid " + (sel ? tag.color : "var(--b2)"),
                  background: sel ? tag.color + "22" : "transparent",
                  color: sel ? tag.color : "var(--t4)", fontSize: 12,
                }
              },
                React.createElement("div", {
                  style: { width: 6, height: 6, borderRadius: "50%", background: tag.color, flexShrink: 0 }
                }),
                tag.name
              );
            })
          )
        ),
        React.createElement("div", { style: { display: "flex", gap: 8 } },
          React.createElement("button", {
            className: "btn-primary",
            style: { fontSize: 13 },
            onClick: handleSave,
            disabled: saving,
          }, saving ? "Saving\u2026" : "Save changes"),
          React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 13 },
            onClick: function () { setEditing(false); },
            disabled: saving,
          }, "Cancel")
        )
      )
    );
  }

  function CollectionPage(props) {
    var slug        = props.slug;
    var currentUser = props.currentUser;
    var _coll     = useState(null);  var coll     = _coll[0];    var setColl     = _coll[1];
    var _loading  = useState(true);  var loading  = _loading[0]; var setLoading  = _loading[1];
    var _deleting = useState(false); var deleting = _deleting[0]; var setDeleting = _deleting[1];

    useEffect(function () {
      apiGet("/collections/" + slug)
        .then(function (d) {
          if (d.collection) setColl(d.collection);
          setLoading(false);
        })
        .catch(function () { setLoading(false); });
    }, [slug]);

    function handleDelete() {
      if (!window.confirm("Delete this collection? Items will not be deleted.")) return;
      setDeleting(true);
      apiDelete("/collections/" + slug)
        .then(function (d) {
          if (d.ok) {
            toast("Collection deleted");
            NE.navigate("/ext/" + SLUG);
          } else {
            toast(d.error || "Failed to delete", "err");
            setDeleting(false);
          }
        })
        .catch(function () { toast("Failed to delete", "err"); setDeleting(false); });
    }

    function handleRemoveItem(itemId) {
      apiDelete("/collections/" + slug + "/items/" + itemId)
        .then(function (d) {
          if (d.ok || d.item_count !== undefined) {
            setColl(function (prev) {
              return Object.assign({}, prev, {
                items:      prev.items.filter(function (i) { return i.id !== itemId; }),
                item_count: Math.max((prev.item_count || 1) - 1, 0),
              });
            });
          } else {
            toast(d.error || "Failed", "err");
          }
        })
        .catch(function () { toast("Failed", "err"); });
    }

    if (loading) return React.createElement("div", {
      style: { textAlign: "center", padding: "80px 0", color: "var(--t5)" }
    }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin", style: { fontSize: 24 } }));

    if (!coll) return React.createElement("div", {
      style: { padding: "80px 0", textAlign: "center", color: "var(--t5)", fontSize: 14 }
    }, "Collection not found.");

    var isOwner = currentUser && (currentUser.id === coll.user_id || currentUser.role === "admin" || currentUser.role === "moderator");

    return React.createElement("div", { style: { maxWidth: 960, margin: "0 auto", padding: "0 0 40px" } },

      // Back button
      React.createElement("button", {
        className: "btn-ghost",
        style: { fontSize: 13, marginBottom: 20, display: "flex", alignItems: "center", gap: 6 },
        onClick: function () { NE.navigate("/ext/" + SLUG); }
      },
        React.createElement("i", { className: "fa-solid fa-arrow-left", style: { fontSize: 11 } }),
        "Gallery"
      ),

      // Header
      React.createElement("div", {
        style: { display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 6, gap: 12 }
      },
        React.createElement("div", null,
          React.createElement("h1", { style: { fontSize: 22, fontWeight: 700, color: "var(--t1)", margin: "0 0 8px" } }, coll.title),
          coll.user && React.createElement("div", {
            style: { display: "flex", alignItems: "center", gap: 8, marginBottom: coll.description ? 10 : 0 }
          },
            React.createElement(Av, { user: coll.user, size: 22 }),
            React.createElement("span", { style: { fontSize: 13, color: "var(--t4)" } }, coll.user.username),
            React.createElement("span", { style: { fontSize: 12, color: "var(--t5)" } },
              "· " + (coll.item_count || 0) + " items"
            )
          ),
          coll.description && React.createElement("p", {
            style: { fontSize: 14, color: "var(--t3)", margin: 0, lineHeight: 1.6 }
          }, coll.description)
        ),
        isOwner && React.createElement("div", { style: { display: "flex", gap: 8, flexShrink: 0 } },
          React.createElement("button", {
            className: "btn-ghost",
            style: { fontSize: 12.5, color: "var(--red)", borderColor: "rgba(239,68,68,0.3)" },
            onClick: handleDelete, disabled: deleting
          },
            React.createElement("i", { className: "fa-solid fa-trash", style: { marginRight: 5 } }),
            deleting ? "Deleting…" : "Delete"
          )
        )
      ),

      // Divider
      React.createElement("div", { style: { height: 1, background: "var(--b1)", margin: "16px 0 20px" } }),

      // Items grid
      (!coll.items || coll.items.length === 0)
        ? React.createElement("div", {
            style: { textAlign: "center", padding: "60px 0", color: "var(--t5)", fontSize: 13 }
          },
            React.createElement("i", { className: "fa-solid fa-layer-group", style: { fontSize: 32, display: "block", marginBottom: 12 } }),
            "No items in this collection yet."
          )
        : React.createElement("div", {
            style: { display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }
          },
            coll.items.map(function (item) {
              return React.createElement("div", { key: item.id, style: { position: "relative" } },
                React.createElement(GalleryCard, { item: item, navigate: NE.navigate }),
                isOwner && React.createElement("button", {
                  onClick: function (e) { e.stopPropagation(); handleRemoveItem(item.id); },
                  title: "Remove from collection",
                  style: {
                    position: "absolute", top: 6, right: 6,
                    background: "rgba(0,0,0,0.6)", border: "none",
                    borderRadius: 6, color: "#fff", cursor: "pointer",
                    width: 26, height: 26, display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 11, zIndex: 2,
                  }
                }, React.createElement("i", { className: "fa-solid fa-xmark" }))
              );
            })
          )
    );
  }
  function GalleryTagPage()     { return React.createElement(Placeholder, { title: "Gallery tag" }); }
  function GalleryUserPage()    { return React.createElement(Placeholder, { title: "Gallery uploads" }); }

  // ─── Right widgets (live in Phase 4) ─────────────────────────────────────

  function GalleryStatsWidget() {
    var _stats = useState(null); var stats = _stats[0]; var setStats = _stats[1];
    useEffect(function () {
      apiGet("/stats").then(function (d) { setStats(d); }).catch(function () {});
    }, []);

    if (!stats) return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Gallery"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Loading…"));

    var statStyle = { background: "var(--s1)", borderRadius: 8, padding: "10px 10px 8px", border: "0.5px solid var(--b1)" };
    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Gallery"),
      React.createElement("div", { style: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 } },
        React.createElement("div", { style: statStyle }, React.createElement("div", { style: { fontSize: 16, fontWeight: 500, color: "var(--t1)" } }, stats.total_images || 0), React.createElement("div", { style: { fontSize: 10, color: "var(--t5)", marginTop: 1 } }, "images")),
        React.createElement("div", { style: statStyle }, React.createElement("div", { style: { fontSize: 16, fontWeight: 500, color: "var(--ac-text)" } }, stats.total_images + stats.total_videos + stats.total_embeds || 0), React.createElement("div", { style: { fontSize: 10, color: "var(--t5)", marginTop: 1 } }, "total")),
        React.createElement("div", { style: statStyle }, React.createElement("div", { style: { fontSize: 16, fontWeight: 500, color: "#34d399" } }, stats.this_week || 0), React.createElement("div", { style: { fontSize: 10, color: "var(--t5)", marginTop: 1 } }, "this week")),
        React.createElement("div", { style: statStyle }, React.createElement("div", { style: { fontSize: 16, fontWeight: 500, color: "#fbbf24" } }, stats.total_videos || 0), React.createElement("div", { style: { fontSize: 10, color: "var(--t5)", marginTop: 1 } }, "videos"))
      )
    );
  }

  function GalleryTopRatedWidget() {
    var _items = useState(null); var items = _items[0]; var setItems = _items[1];
    useEffect(function () {
      apiGet("/top-rated?limit=4").then(function (d) { if (d.items) setItems(d.items); }).catch(function () {});
    }, []);

    if (!items) return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Top rated"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Loading…"));

    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top rated"),
      items.length === 0
        ? React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "No items yet.")
        : items.map(function (item) {
            return React.createElement("div", {
              key: item.id,
              onClick: function () { NE.navigate("/ext/" + SLUG + "/" + item.id); },
              style: { display: "flex", alignItems: "center", gap: 7, padding: "4px 0", cursor: "pointer" }
            },
              React.createElement("div", { style: { width: 22, height: 22, borderRadius: 6, background: "var(--s2)", flexShrink: 0, overflow: "hidden" } },
                (item.thumbnail_url || item.file_url) && React.createElement("img", { src: item.thumbnail_url || item.file_url, style: { width: "100%", height: "100%", objectFit: "cover" } })
              ),
              React.createElement("span", { style: { fontSize: 12, color: "var(--t3)", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, item.title || "Untitled"),
              React.createElement("span", { style: { fontSize: 11, color: "var(--t5)", flexShrink: 0, display: "flex", alignItems: "center", gap: 3 } },
                React.createElement("i", { className: "fa-solid fa-eye", style: { fontSize: 9 } }),
                item.view_count || 0
              )
            );
          })
    );
  }

  function GalleryTagsWidget() {
    var _tags = useState(null); var tags = _tags[0]; var setTags = _tags[1];
    useEffect(function () {
      apiGet("/tags/public").then(function (d) { if (d.tags) setTags(d.tags.slice(0, 6)); }).catch(function () {});
    }, []);

    if (!tags) return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Tags"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Loading…"));

    var maxCount = tags.reduce(function (m, t) { return Math.max(m, t.item_count || 0); }, 1);

    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Tags"),
      tags.length === 0
        ? React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "No tags yet.")
        : tags.map(function (tag) {
            var pct = maxCount > 0 ? Math.round(((tag.item_count || 0) / maxCount) * 100) : 0;
            return React.createElement("div", {
              key: tag.id,
              onClick: function () { NE.navigate("/ext/" + SLUG + "?tag=" + tag.slug); }
            },
              React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 6, padding: "4px 0", cursor: "pointer" } },
                React.createElement("div", { style: { width: 7, height: 7, borderRadius: "50%", background: tag.color, flexShrink: 0 } }),
                React.createElement("span", { style: { fontSize: 12, color: "var(--t3)", flex: 1 } }, tag.name),
                React.createElement("span", { style: { fontSize: 11, color: "var(--t5)" } }, tag.item_count || 0)
              ),
              React.createElement("div", { style: { height: 3, background: "var(--b1)", borderRadius: 2, marginBottom: 5, overflow: "hidden" } },
                React.createElement("div", { style: { height: 3, borderRadius: 2, background: tag.color, width: pct + "%" } })
              )
            );
          })
    );
  }

  function GalleryTopUploadersWidget() {
    var _data = useState(null); var data = _data[0]; var setData = _data[1];
    useEffect(function () {
      apiGet("/top-uploaders?limit=4").then(function (d) { if (d.uploaders) setData(d.uploaders); }).catch(function () {});
    }, []);

    if (!data) return React.createElement("div", { className: "rw" }, React.createElement("div", { className: "rw-label" }, "Top uploaders"), React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Loading…"));

    return React.createElement("div", { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top uploaders"),
      data.length === 0
        ? React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "No uploads yet.")
        : data.map(function (row) {
            return row.user && React.createElement("div", {
              key: row.user.id,
              style: { display: "flex", alignItems: "center", gap: 7, padding: "4px 0", cursor: "pointer" },
              onClick: function () { NE.navigate("/ext/" + SLUG + "/user/" + row.user.username); }
            },
              React.createElement(Av, { user: row.user, size: 22 }),
              React.createElement("span", { style: { fontSize: 12, color: "var(--t3)", flex: 1 } }, row.user.username),
              React.createElement("span", { style: { fontSize: 11.5, color: "var(--ac-text)", fontWeight: 500, flexShrink: 0 } }, row.count)
            );
          })
    );
  }

  // ─── Admin panel ──────────────────────────────────────────────────────────

  function TagForm(props) {
    var initial = props.initial; var onSave = props.onSave; var onCancel = props.onCancel;
    var _form = useState(initial || { name: "", color: "#7c5cfc", allow_images: true, allow_videos: true, allow_embeds: true });
    var form = _form[0]; var setForm = _form[1];
    var _saving = useState(false); var saving = _saving[0]; var setSaving = _saving[1];

    function handleSubmit() {
      if (!form.name.trim()) { toast("Name is required", "err"); return; }
      setSaving(true);
      onSave(form).finally(function () { setSaving(false); });
    }

    var ss = { fontSize: 12, color: "var(--t4)", fontWeight: 500, marginBottom: 6 };
    var is = { width: "100%", padding: "8px 12px", background: "rgba(255,255,255,0.05)", border: "0.5px solid var(--b2)", borderRadius: 10, color: "var(--t1)", fontSize: 14, outline: "none", fontFamily: "inherit" };

    return React.createElement("div", { style: { background: "var(--s2)", border: "0.5px solid var(--b2)", borderRadius: 12, padding: "16px 18px", marginBottom: 10 } },
      React.createElement("div", { style: { marginBottom: 14 } }, React.createElement("div", { style: ss }, "Name"), React.createElement("input", { style: is, value: form.name, placeholder: "Tag name", autoFocus: true, onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { name: e.target.value }); }); } })),
      React.createElement("div", { style: { marginBottom: 14 } },
        React.createElement("div", { style: ss }, "Color"),
        React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10 } },
          React.createElement("input", { style: Object.assign({}, is, { maxWidth: 130 }), value: form.color, placeholder: "#7c5cfc", onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); } }),
          React.createElement("input", { type: "color", value: form.color || "#7c5cfc", onChange: function (e) { setForm(function (p) { return Object.assign({}, p, { color: e.target.value }); }); }, style: { width: 36, height: 36, border: "none", borderRadius: 6, cursor: "pointer", background: "none" } }),
          React.createElement("div", { style: { width: 28, height: 28, borderRadius: "50%", background: form.color || "#7c5cfc", flexShrink: 0 } })
        )
      ),
      React.createElement("div", { style: { marginBottom: 16 } },
        React.createElement("div", { style: ss }, "Allowed media types"),
        ["Images", "Videos", "Embeds"].map(function (label) {
          var key = "allow_" + label.toLowerCase();
          return React.createElement("div", { key: key, style: { display: "flex", alignItems: "center", gap: 10, padding: "6px 0" } },
            React.createElement(Toggle, { value: form[key], onChange: function (v) { setForm(function (p) { var u = Object.assign({}, p); u[key] = v; return u; }); }, label: label })
          );
        })
      ),
      React.createElement("div", { style: { display: "flex", gap: 8 } },
        React.createElement("button", { className: "btn-primary", style: { fontSize: 13, padding: "7px 16px" }, onClick: handleSubmit, disabled: saving }, saving ? "Saving…" : (initial ? "Save changes" : "Create tag")),
        React.createElement("button", { className: "btn-ghost",   style: { fontSize: 13, padding: "7px 16px" }, onClick: onCancel, disabled: saving }, "Cancel")
      )
    );
  }

  function TagRow(props) {
    var tag = props.tag; var onEdit = props.onEdit; var onDelete = props.onDelete;
    var bs = function (color, active) { return { fontSize: 10, padding: "1px 6px", borderRadius: 4, fontWeight: 500, background: active ? color + "22" : "rgba(255,255,255,0.04)", color: active ? color : "var(--t5)", border: "0.5px solid " + (active ? color + "44" : "var(--b1)") }; };
    return React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 10, padding: "10px 0", borderBottom: "0.5px solid var(--b1)" } },
      React.createElement("div", { style: { color: "var(--t5)", cursor: "grab", fontSize: 13, flexShrink: 0 } }, React.createElement("i", { className: "fa-solid fa-grip-vertical" })),
      React.createElement("div", { style: { width: 10, height: 10, borderRadius: "50%", background: tag.color, flexShrink: 0 } }),
      React.createElement("span", { style: { fontSize: 13, color: "var(--t2)", fontWeight: 500, flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, tag.name),
      React.createElement("div", { style: { display: "flex", gap: 4 } },
        React.createElement("span", { style: bs("#60a5fa", tag.allow_images) }, "IMG"),
        React.createElement("span", { style: bs("#fbbf24", tag.allow_videos) }, "VID"),
        React.createElement("span", { style: bs("#a78bfa", tag.allow_embeds) }, "EMB")
      ),
      React.createElement("span", { style: { fontSize: 11.5, color: "var(--t5)", minWidth: 28, textAlign: "right", flexShrink: 0 } }, tag.item_count),
      React.createElement("button", { onClick: function () { onEdit(tag); }, style: { fontSize: 11.5, padding: "3px 9px", borderRadius: 8, border: "0.5px solid var(--b2)", color: "var(--t4)", background: "transparent", cursor: "pointer", fontFamily: "inherit" } }, React.createElement("i", { className: "fa-solid fa-pen" })),
      React.createElement("button", { onClick: function () { onDelete(tag); }, style: { fontSize: 11.5, padding: "3px 9px", borderRadius: 8, border: "0.5px solid rgba(248,113,113,0.3)", color: "var(--red)", background: "transparent", cursor: "pointer", fontFamily: "inherit" } }, React.createElement("i", { className: "fa-solid fa-trash" }))
    );
  }

  function TagsTab() {
    var _tags    = useState(null);  var tags    = _tags[0];    var setTags    = _tags[1];
    var _loading = useState(true);  var loading = _loading[0]; var setLoading = _loading[1];
    var _creating= useState(false); var creating= _creating[0];var setCreating = _creating[1];
    var _editing = useState(null);  var editing = _editing[0]; var setEditing  = _editing[1];
    var dragIdx  = useRef(null);    var overIdx  = useRef(null);

    function load() {
      setLoading(true);
      apiGet("/tags").then(function (d) { setTags(d.tags || []); setLoading(false); })
        .catch(function () { toast("Failed to load tags", "err"); setLoading(false); });
    }
    useEffect(load, []);

    function handleCreate(form) { return apiPost("/tags", form).then(function (d) { if (d.tag) { setTags(function (p) { return p.concat(d.tag); }); setCreating(false); toast("Tag created"); } else toast(d.error || "Failed", "err"); }); }
    function handleEdit(form)   { return apiPatch("/tags/" + editing.id, form).then(function (d) { if (d.tag) { setTags(function (p) { return p.map(function (t) { return t.id === d.tag.id ? d.tag : t; }); }); setEditing(null); toast("Tag updated"); } else toast(d.error || "Failed", "err"); }); }
    function handleDelete(tag)  {
      if (!window.confirm("Delete tag \"" + tag.name + "\"?")) return;
      apiDelete("/tags/" + tag.id).then(function (d) { if (d.ok) { setTags(function (p) { return p.filter(function (t) { return t.id !== tag.id; }); }); toast("Tag deleted"); } else toast(d.error || "Failed", "err"); });
    }
    function handleDrop() {
      var from = dragIdx.current; var to = overIdx.current;
      if (from === null || to === null || from === to) return;
      var r = tags.slice(); var m = r.splice(from, 1)[0]; r.splice(to, 0, m);
      setTags(r); dragIdx.current = null; overIdx.current = null;
      apiPost("/tags/reorder", { ids: r.map(function (t) { return t.id; }) }).then(function (d) { if (!d.ok) toast("Failed to save order", "err"); });
    }

    if (loading) return React.createElement("div", { style: { padding: "48px 0", textAlign: "center", color: "var(--t5)" } }, React.createElement("i", { className: "fa-solid fa-spinner fa-spin" }));

    return React.createElement("div", null,
      React.createElement("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 } },
        React.createElement("div", { style: { fontSize: 13, color: "var(--t4)" } }, (tags ? tags.length : 0) + " tags · drag to reorder"),
        !creating && React.createElement("button", { className: "btn-ghost", style: { fontSize: 12.5, display: "flex", alignItems: "center", gap: 6 }, onClick: function () { setCreating(true); setEditing(null); } }, React.createElement("i", { className: "fa-solid fa-plus" }), " New tag")
      ),
      creating && React.createElement(TagForm, { onSave: handleCreate, onCancel: function () { setCreating(false); } }),
      tags && tags.length === 0 && !creating && React.createElement("div", { style: { padding: "32px 0", textAlign: "center", color: "var(--t5)", fontSize: 13 } }, "No tags yet."),
      tags && tags.map(function (tag, i) {
        if (editing && editing.id === tag.id) return React.createElement(TagForm, { key: tag.id, initial: tag, onSave: handleEdit, onCancel: function () { setEditing(null); } });
        return React.createElement("div", { key: tag.id, draggable: true, onDragStart: function () { dragIdx.current = i; }, onDragOver: function (e) { e.preventDefault(); overIdx.current = i; }, onDrop: handleDrop },
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
    var tmpl = window.NexusExtensionTemplates;
    return React.createElement(tmpl.TabbedPanel, {
      tabs: [
        { key: "general", label: "General", icon: "fa-gear", render: function () {
          return React.createElement(tmpl.SimpleSettingsPanel, { slug: SLUG, fields: [
            { key: "gallery_enabled",         label: "Gallery enabled",       type: "boolean", hint: "Show Gallery in the Explore sidebar and make all routes accessible." },
            { key: "ratings_enabled",          label: "Ratings enabled",       type: "boolean", hint: "Allow members to give 1–5 star ratings on images, videos, and collections." },
            { key: "comments_enabled",         label: "Comments enabled",      type: "boolean", hint: "Allow members to comment on gallery items and collections." },
            { key: "reactions_enabled",        label: "Reactions enabled",     type: "boolean", hint: "Allow members to react to gallery items and collections with emoji." },
            { key: "block_self_reactions",     label: "Block self-reactions",  type: "boolean", hint: "Prevent members from reacting to their own gallery items. Enabled by default." },
            { key: "block_self_ratings",       label: "Block self-ratings",    type: "boolean", hint: "Prevent members from rating their own gallery items. Enabled by default." },
            { key: "moderation_queue_enabled", label: "Moderation queue",      type: "boolean", hint: "New uploads go into a pending queue and require admin approval before appearing publicly." },
            { key: "max_tags_per_item",        label: "Max tags per item",     type: "number",  hint: "Maximum number of tags a member can apply to a single item." },
            { key: "max_collection_size",      label: "Max collection size",   type: "number",  hint: "Maximum number of items a collection can contain." },
            { key: "items_per_page",           label: "Items per page",        type: "select",  options: [{ value: "24", label: "24" }, { value: "36", label: "36" }, { value: "48", label: "48" }, { value: "60", label: "60" }] },
            { key: "videos_enabled",           label: "Video uploads enabled", type: "boolean", hint: "Allow members to upload video files (MP4, WebM). Disabled by default." },
            { key: "max_video_size_mb",        label: "Max video size (MB)",   type: "number",  hint: "Per-file size cap for video uploads." },
          ] });
        } },
        { key: "tags",    label: "Tags",    icon: "fa-tag",       render: function () { return React.createElement(TagsTab); } },
        { key: "queue",   label: "Queue",   icon: "fa-clock",     render: function () { return React.createElement(ComingSoonTab, { label: "Moderation queue" }); } },
        { key: "harvest", label: "Harvest", icon: "fa-seedling",  render: function () { return React.createElement(ComingSoonTab, { label: "Image harvest configuration" }); } },
        { key: "stats",   label: "Stats",   icon: "fa-chart-bar", render: function () { return React.createElement(ComingSoonTab, { label: "Gallery stats" }); } },
      ]
    });
  }

  // ─── Profile tab ─────────────────────────────────────────────────────────

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
