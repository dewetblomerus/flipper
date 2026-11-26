defmodule FlipperWeb.DraftRefreshTest do
  use FlipperWeb.ConnCase, async: false
  use Oban.Testing, repo: Flipper.Repo

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Flipper.Drafts
  alias Flipper.Ebay.Session
  alias Flipper.Workers.FetchDraft
  alias Flipper.Workers.ImportDrafts

  setup do
    path = Application.fetch_env!(:flipper, :ebay_cookie_path)
    :ok = Session.set("secret-value")

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> ".rejected")
      Session.refresh()
    end)
  end

  test "queues one import in the ebay queue", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/drafts")

    view |> element("#refresh-drafts") |> render_click()

    assert has_element?(view, "#refresh-drafts[disabled]", "Refreshing")
    assert {:ok, %{conflict?: true}} = Drafts.refresh_list()
    assert [_] = all_enqueued(worker: ImportDrafts)
    assert_enqueued(queue: :ebay, worker: ImportDrafts)
  end

  test "takes over an import waiting in the paced queue" do
    {:ok, _job} = Oban.insert(ImportDrafts.new(%{}))

    assert {:ok, _job} = Drafts.refresh_list()

    assert [%{queue: "ebay"}] = all_enqueued(worker: ImportDrafts)
  end

  test "lists the new drafts once the import finishes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/drafts")
    view |> element("#refresh-drafts") |> render_click()
    Process.put(:ebay_drafts, {:ok, [listed("123456")]})

    assert :ok = perform_job(ImportDrafts, %{})

    html = render(view)
    assert html =~ "123456"
    assert html =~ "Drafts refreshed."
    assert has_element?(view, "#refresh-drafts:not([disabled])", "Refresh Drafts")
  end

  test "shows why a refresh failed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/drafts")
    view |> element("#refresh-drafts") |> render_click()
    Process.put(:ebay_drafts, {:error, "eBay returned 500"})

    capture_log(fn -> perform_job(ImportDrafts, %{}) end)

    assert render(view) =~ "Refresh failed: eBay returned 500"
    assert has_element?(view, "#refresh-drafts:not([disabled])")
  end

  test "an import nobody asked for updates the list quietly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/drafts")
    Process.put(:ebay_drafts, {:ok, [listed("123456")]})

    assert :ok = perform_job(ImportDrafts, %{})

    html = render(view)
    assert html =~ "123456"
    refute html =~ "Drafts refreshed."
  end

  test "the list follows a draft as it is read", %{conn: conn} do
    {:ok, draft} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=1")
    {:ok, view, html} = live(conn, ~p"/drafts")
    refute html =~ "Vintage lamp"

    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})

    assert render(view) =~ "Vintage lamp"
  end

  defp listed(ebay_draft_id) do
    %{ebay_draft_id: ebay_draft_id, title: "Listed lamp", sku: "", photo?: false}
  end
end
