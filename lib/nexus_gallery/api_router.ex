defmodule NexusGallery.ApiRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  # -------------------------------------------------------------------------
  # Phase 1 health check — verifies routing is wired correctly.
  # Testable: GET /ext/nexus-gallery/api/ping → 200 {ok: true}
  # -------------------------------------------------------------------------

  get "/ping" do
    send_resp(conn, 200, Jason.encode!(%{ok: true, extension: "nexus-gallery"}))
  end

  # -------------------------------------------------------------------------
  # Catch-all — returns 404 for any unimplemented route.
  # -------------------------------------------------------------------------

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
  end
end
