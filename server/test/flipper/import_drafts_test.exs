defmodule Flipper.ImportDraftsTest do
  use Flipper.DataCase, async: false
  use Oban.Testing, repo: Flipper.Repo

  import ExUnit.CaptureLog

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft
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

  test "adds only unknown drafts and queues their reads in the paced queue" do
    {:ok, pasted} = paste("1")
    list([listed("1", "A-1"), listed("22", "A-2"), listed("22", "A-2")])

    assert :ok = perform_job(ImportDrafts, %{})

    assert [_, %Draft{state: "started"} = imported] = Repo.all(from d in Draft, order_by: d.id)
    assert imported.ebay_draft_id == "22"
    assert [job] = all_enqueued(queue: :ebay_automated)
    assert job.args == %{"draft_id" => imported.id}
    assert [job] = all_enqueued(queue: :ebay)
    assert job.args == %{"draft_id" => pasted.id}

    finish_jobs()
    assert :ok = perform_job(ImportDrafts, %{})
    assert [] = all_enqueued(worker: FetchDraft)
  end

  test "a draft listed without a SKU or a photo waits unread" do
    list([listed("1", ""), listed("22", "A-2", false), listed("33", "", false)])

    assert :ok = perform_job(ImportDrafts, %{})

    assert [first, second, third] = Repo.all(from d in Draft, order_by: d.id)
    assert Enum.all?([first, second, third], &(&1.state == "awaiting_sku"))
    assert Enum.map([first, second, third], & &1.sku) == [nil, "A-2", nil]
    assert first.title == "Listed 1"
    assert [] = all_enqueued(worker: FetchDraft)
  end

  test "saves each listing's age, on new drafts and known ones" do
    created = ~U[2026-11-10 17:00:00.000000Z]
    {:ok, pasted} = paste("1")
    list([listed("1", "", false, created), listed("22", "", false, created)])

    assert :ok = perform_job(ImportDrafts, %{})
    assert [created, created] == Repo.all(from d in Draft, select: d.listed_at)

    list([listed("1", "", false), listed("22", "", false)])
    assert :ok = perform_job(ImportDrafts, %{})
    assert Repo.get!(Draft, pasted.id).listed_at == created
  end

  test "a paste or a refresh takes over a waiting import" do
    list([listed("1", "A-1"), listed("22", "A-2")])
    assert :ok = perform_job(ImportDrafts, %{})

    {:ok, pasted} = paste("1")
    refreshed = Repo.get_by!(Draft, ebay_draft_id: "22")
    {:ok, _draft} = Drafts.refresh(refreshed)

    assert [] = all_enqueued(queue: :ebay_automated)

    assert Enum.sort(Enum.map(all_enqueued(queue: :ebay), & &1.args["draft_id"])) ==
             Enum.sort([pasted.id, refreshed.id])
  end

  test "reads a waiting draft once the list shows both its SKU and a photo" do
    list([listed("22", "", false)])
    assert :ok = perform_job(ImportDrafts, %{})
    waiting = Repo.get_by!(Draft, ebay_draft_id: "22")

    list([listed("22", "A-2", false)])
    assert :ok = perform_job(ImportDrafts, %{})
    assert Repo.get!(Draft, waiting.id).sku == "A-2"
    assert [] = all_enqueued(worker: FetchDraft)

    list([listed("22", "A-2")])
    assert :ok = perform_job(ImportDrafts, %{})
    assert_enqueued(queue: :ebay_automated, worker: FetchDraft, args: %{draft_id: waiting.id})

    assert :ok = perform_job(FetchDraft, %{draft_id: waiting.id})
    assert Repo.get!(Draft, waiting.id).state == "photos_taken"
  end

  test "reads a pasted draft that waits as soon as the list shows both" do
    waiting = waiting_draft("11")
    list([listed("11", "A-2")])

    assert :ok = perform_job(ImportDrafts, %{})

    assert_enqueued(queue: :ebay_automated, worker: FetchDraft, args: %{draft_id: waiting.id})
  end

  test "a failed read insertion leaves a waiting draft eligible for another import" do
    waiting = waiting_draft("11")
    list([listed("11", "A-2")])

    Repo.query!("""
    ALTER TABLE oban_jobs ADD CONSTRAINT reject_automated_read
      CHECK (queue <> 'ebay_automated')
    """)

    assert_raise Ecto.ConstraintError, ~r/reject_automated_read/, fn ->
      Drafts.import_from_ebay()
    end

    assert Repo.get!(Draft, waiting.id).import_read_at == nil
    Repo.query!("ALTER TABLE oban_jobs DROP CONSTRAINT reject_automated_read")

    assert :ok = perform_job(ImportDrafts, %{})
    assert_enqueued(queue: :ebay_automated, worker: FetchDraft, args: %{draft_id: waiting.id})
  end

  test "skips a read that another import queues after this one loads its drafts" do
    waiting_draft("11")
    list([listed("11", "A-2")])

    after_drafts_load(fn -> Repo.update_all(Draft, set: [import_read_at: DateTime.utc_now()]) end)

    assert :ok = perform_job(ImportDrafts, %{})
    assert [] = all_enqueued(worker: FetchDraft)
  end

  test "queues a draft's read at most once a day, even when its page shows no SKU" do
    list([listed("11", "A-2")])
    assert :ok = perform_job(ImportDrafts, %{})
    draft = Repo.get_by!(Draft, ebay_draft_id: "11")
    assert :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    finish_jobs()
    assert Repo.get!(Draft, draft.id).state == "awaiting_sku"

    assert :ok = perform_job(ImportDrafts, %{})
    assert [] = all_enqueued(worker: FetchDraft)

    day_ago = DateTime.add(DateTime.utc_now(), -25, :hour)

    Repo.get!(Draft, draft.id)
    |> Ecto.Changeset.change(import_read_at: day_ago)
    |> Repo.update!()

    assert :ok = perform_job(ImportDrafts, %{})
    assert_enqueued(queue: :ebay_automated, worker: FetchDraft, args: %{draft_id: draft.id})
  end

  test "leaves a waiting draft with a failed read to a person" do
    list([listed("22", "", false)])
    assert :ok = perform_job(ImportDrafts, %{})
    waiting = Repo.get_by!(Draft, ebay_draft_id: "22")
    :ok = Drafts.record_fetch_error(waiting, "eBay returned 500")

    list([listed("22", "A-2")])

    assert :ok = perform_job(ImportDrafts, %{})
    assert [] = all_enqueued(worker: FetchDraft)
  end

  test "a rejected cookie stops the list read and unattended draft reads" do
    {:ok, draft} = paste("1")
    :ok = Session.reject("secret-value")

    assert {:cancel, _} = perform_job(ImportDrafts, %{})
    assert {:cancel, _} = ImportDrafts.run()
    refute_received :ebay_drafts_listed

    assert {:cancel, _} =
             perform_job(FetchDraft, %{draft_id: draft.id}, queue: :ebay_automated)

    draft = Drafts.get_draft!(draft.id)
    assert draft.photos == []
    assert draft.fetch_error == "eBay cookie needs attention"
  end

  test "a failed list read is logged and adds nothing" do
    Process.put(:ebay_drafts, {:error, "eBay returned 500"})

    log =
      capture_log(fn ->
        assert {:error, "eBay returned 500"} = perform_job(ImportDrafts, %{})
      end)

    assert log =~ "eBay drafts import failed: eBay returned 500"
    assert Repo.aggregate(Draft, :count) == 0
  end

  defp paste(ebay_draft_id) do
    Drafts.paste_url("https://www.ebay.com/lstng?draft_id=#{ebay_draft_id}")
  end

  # Draft "11" has photos and no SKU.
  defp waiting_draft(ebay_draft_id) do
    {:ok, draft} = paste(ebay_draft_id)
    :ok = perform_job(FetchDraft, %{draft_id: draft.id})
    finish_jobs()
    Drafts.get_draft!(draft.id)
  end

  defp listed(ebay_draft_id, sku, photo? \\ true, listed_at \\ nil) do
    %{
      ebay_draft_id: ebay_draft_id,
      title: "Listed #{ebay_draft_id}",
      sku: sku,
      photo?: photo?,
      listed_at: listed_at
    }
  end

  defp list(drafts), do: Process.put(:ebay_drafts, {:ok, drafts})

  defp finish_jobs, do: Repo.update_all(Oban.Job, set: [state: "completed"])

  # Runs the function once, right after this process next reads the drafts table.
  defp after_drafts_load(function) do
    test = self()
    id = make_ref()

    handler = fn _event, _measurements, %{source: source, query: query}, nil ->
      if self() == test and source == "drafts" and String.starts_with?(query, "SELECT") do
        :telemetry.detach(id)
        function.()
      end
    end

    :ok = :telemetry.attach(id, [:flipper, :repo, :query], handler, nil)
  end
end
