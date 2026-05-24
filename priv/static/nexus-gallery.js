(function () {
  "use strict";

  const NE   = window.NexusExtensions;
  const SLUG = "nexus-gallery";
  const { useState, useEffect } = window.React;

  // ─── Placeholder component ───────────────────────────────────────────────
  // Used for every route in Phase 1. Renders the route title so navigation
  // can be verified without any real content.

  function Placeholder({ title }) {
    return React.createElement(
      "div",
      { style: { padding: "48px 0", textAlign: "center", color: "var(--t4)", fontSize: 14 } },
      React.createElement("i", {
        className: "fa-solid fa-images",
        style: { fontSize: 32, display: "block", marginBottom: 16, color: "var(--t5)" },
      }),
      React.createElement("div", { style: { fontWeight: 500, color: "var(--t2)", marginBottom: 8 } }, title),
      React.createElement("div", null, "Coming in a future phase.")
    );
  }

  // ─── Route components (Phase 1 stubs) ────────────────────────────────────

  function GalleryPage()           { return React.createElement(Placeholder, { title: "Gallery" }); }
  function GalleryItemPage()       { return React.createElement(Placeholder, { title: "Gallery item" }); }
  function CollectionPage()        { return React.createElement(Placeholder, { title: "Collection" }); }
  function GalleryTagPage()        { return React.createElement(Placeholder, { title: "Gallery tag" }); }
  function GalleryUserPage()       { return React.createElement(Placeholder, { title: "Gallery uploads" }); }
  function NewGalleryItemPage()    { return React.createElement(Placeholder, { title: "New gallery item" }); }

  // ─── Admin panel component (Phase 1 stub) ────────────────────────────────

  function GalleryAdminPanel() {
    return React.createElement(Placeholder, { title: "Gallery admin panel" });
  }

  // ─── Right widget components (Phase 1 stubs) ─────────────────────────────

  function GalleryStatsWidget() {
    return React.createElement(
      "div",
      { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Gallery"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Stats coming soon.")
    );
  }

  function GalleryTopRatedWidget() {
    return React.createElement(
      "div",
      { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top rated"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  function GalleryTagsWidget() {
    return React.createElement(
      "div",
      { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Tags"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  function GalleryTopUploadersWidget() {
    return React.createElement(
      "div",
      { className: "rw" },
      React.createElement("div", { className: "rw-label" }, "Top uploaders"),
      React.createElement("div", { style: { fontSize: 12, color: "var(--t5)" } }, "Coming soon.")
    );
  }

  // ─── Profile tab component (Phase 1 stub) ────────────────────────────────

  function GalleryProfileTab({ username }) {
    return React.createElement(Placeholder, { title: "Gallery uploads for " + username });
  }

  // ─── Register routes ─────────────────────────────────────────────────────
  // Paths must exactly match the routes declared in manifest.json.

  NE.registerRoute(SLUG, "/",                 GalleryPage,        { title: "Gallery" });
  NE.registerRoute(SLUG, "/:uuid",            GalleryItemPage,    { title: "Gallery item" });
  NE.registerRoute(SLUG, "/collection/:slug", CollectionPage,     { title: "Collection" });
  NE.registerRoute(SLUG, "/tag/:slug",        GalleryTagPage,     { title: "Gallery tag" });
  NE.registerRoute(SLUG, "/user/:username",   GalleryUserPage,    { title: "Gallery uploads" });
  NE.registerRoute(SLUG, "/new/:uuid",        NewGalleryItemPage, { title: "New gallery item" });

  // ─── Register admin panel ────────────────────────────────────────────────

  NE.registerAdminPanel(SLUG, {
    label:     "Gallery",
    icon:      "fa-images",
    component: GalleryAdminPanel,
  });

  // ─── Register Explore item ───────────────────────────────────────────────

  NE.registerExploreItem({
    slug:     SLUG,
    path:     "/",
    label:    "Gallery",
    icon:     "fa-images",
    authOnly: false,
    priority: 50,
  });

  // ─── Register right widgets ──────────────────────────────────────────────
  // IDs must exactly match those declared in manifest.json right_widgets.

  NE.registerRightWidget({
    slug:      SLUG,
    id:        "gallery-stats",
    label:     "Gallery stats",
    component: GalleryStatsWidget,
    scope:     "extension",
    priority:  10,
  });

  NE.registerRightWidget({
    slug:      SLUG,
    id:        "gallery-top-rated",
    label:     "Gallery top rated",
    component: GalleryTopRatedWidget,
    scope:     "extension",
    priority:  20,
  });

  NE.registerRightWidget({
    slug:      SLUG,
    id:        "gallery-tags",
    label:     "Gallery tags",
    component: GalleryTagsWidget,
    scope:     "extension",
    priority:  30,
  });

  NE.registerRightWidget({
    slug:      SLUG,
    id:        "gallery-top-uploaders",
    label:     "Gallery top uploaders",
    component: GalleryTopUploadersWidget,
    scope:     "extension",
    priority:  40,
  });

  // ─── Register profile tab ────────────────────────────────────────────────

  NE.registerProfileTab({
    slug:      SLUG,
    id:        "gallery-uploads",
    component: GalleryProfileTab,
  });

  // ─── Register notification types ─────────────────────────────────────────
  // Declared in manifest.json notification_types — must match keys exactly.

  NE.registerNotificationType("gallery_comment", {
    icon:      "fa-comment",
    iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(
        React.Fragment,
        null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",  { style: { color: "var(--t3)" } }, " commented on your gallery item.")
      );
    },
    onClick: function (_ref) {},
  });

  NE.registerNotificationType("gallery_rating", {
    icon:      "fa-star",
    iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(
        React.Fragment,
        null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",  { style: { color: "var(--t3)" } }, " rated your gallery item.")
      );
    },
    onClick: function (_ref) {},
  });

  NE.registerNotificationType("gallery_new_image", {
    icon:      "fa-images",
    iconColor: "var(--ac)",
    renderBody: function (n) {
      return React.createElement(
        React.Fragment,
        null,
        React.createElement("strong", { style: { color: "var(--t1)" } }, n.actor ? n.actor.username : "Someone"),
        React.createElement("span",  { style: { color: "var(--t3)" } }, " added a new image to a tag you follow.")
      );
    },
    onClick: function (_ref) {},
  });

})();
