defmodule FlipperWeb.EbayCookieLiveTest do
  use FlipperWeb.ConnCase, async: false
  use Oban.Testing, repo: Flipper.Repo

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Flipper.Drafts
  alias Flipper.Ebay.Session
  alias Flipper.Repo
  alias Flipper.Workers.FetchDraft

  setup do
    path = Application.fetch_env!(:flipper, :ebay_cookie_path)
    rejected = path <> ".rejected"
    previous = Application.get_env(:flipper, :ebay_cookie)
    File.rm(path)
    File.rm(rejected)
    Application.put_env(:flipper, :ebay_cookie, nil)
    Session.refresh()

    on_exit(fn ->
      File.rm(path)
      File.rm(rejected)

      if is_binary(previous) and previous != "" do
        Application.put_env(:flipper, :ebay_cookie, previous)
      else
        Application.delete_env(:flipper, :ebay_cookie)
      end

      Session.refresh()
    end)

    %{path: path}
  end

  test "the field takes focus", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)

    assert has_element?(
             view,
             ~s(textarea[autofocus][phx-hook="FlipperWeb.EbayCookieLive.PasteTarget"])
           )
  end

  test "closes when another server saves the cookie", %{conn: conn, path: path} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)

    File.write!(path, "other-server")
    :ok = Session.refresh()

    refute has_element?(view, "#ebay-cookie-popover")
  end

  test "asks for a missing cookie and closes once it is saved", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)
    assert has_element?(view, "#ebay-cookie-popover", "Add your eBay cookie")

    save_cookie(view, "   ")
    assert has_element?(view, "#ebay-cookie-form", "is blank")
    assert is_nil(Session.cookie())

    html = save_cookie(view, "cookie: secret-value")
    refute has_element?(view, "#ebay-cookie-popover")
    assert has_element?(view, "#ebay-cookie-saved", "eBay cookie saved.")
    refute html =~ "secret-value"
    assert Session.cookie() == "secret-value"
  end

  test "saving keeps the cookie out of the logs", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)
    level = Logger.level()
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      capture_log(fn ->
        Logger.configure(level: :debug)
        save_cookie(view, "secret-value")
        Logger.configure(level: level)
      end)

    assert log =~ ~s("ebay_cookie" => "[FILTERED]")
    refute log =~ "secret-value"
  end

  test "reopens empty when eBay rejects the cookie", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)
    save_cookie(view, "secret-value")

    :ok = Session.reject("secret-value", 429, "eBay returned 429")

    assert has_element?(view, "#ebay-cookie-popover", "eBay rejected the cookie")
    assert has_element?(view, "#ebay-cookie-reason", "eBay returned 429")
    refute has_element?(view, "#ebay-cookie-saved")
    refute render(view) =~ "secret-value"
  end

  test "closes when the cookie is saved from another page", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)

    :ok = Session.set("secret-value")

    refute has_element?(view, "#ebay-cookie-popover")
  end

  test "saving retries a failed read", %{conn: conn} do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=404")
    {:error, _} = perform_job(FetchDraft, %{draft_id: draft.id}, attempt: 3)
    Repo.update_all(Oban.Job, set: [state: "discarded"])
    {:ok, view, _html} = live_isolated(conn, FlipperWeb.EbayCookieLive)

    save_cookie(view, "secret-value")

    assert_enqueued(priority: 2, worker: FetchDraft, args: %{draft_id: draft.id})
    assert Drafts.get_draft!(draft.id).fetch_error == nil
  end

  test "every page has the popover only while the cookie is needed", %{conn: conn} do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=1")
    paths = [~p"/", ~p"/drafts", ~p"/drafts/new", ~p"/drafts/#{draft}", ~p"/auto"]

    for path <- paths, do: assert(popover?(conn, path))

    :ok = Session.set("secret-value")

    for path <- paths, do: refute(popover?(conn, path))
  end

  defp save_cookie(view, value) do
    view
    |> form("#ebay-cookie-form", ebay_cookie: %{value: value})
    |> render_submit()
  end

  # The popover is its own LiveView in the root layout, outside each page's view.
  defp popover?(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#ebay-cookie-popover")
    |> LazyHTML.to_tree() != []
  end
end
