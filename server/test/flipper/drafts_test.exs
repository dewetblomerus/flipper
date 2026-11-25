defmodule Flipper.DraftsTest do
  use Flipper.DataCase, async: true

  alias Flipper.Drafts
  alias Flipper.Drafts.Draft

  @url "https://www.ebay.com/lstng?mode=SellLikeItem&draft_id=5345502780022&ReturnURL=https%3A%2F%2Fwww.ebay.com%2Fsh%2Flst%2Fdrafts"

  test "list_drafts returns newest first" do
    assert {:ok, older} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=1")
    assert {:ok, newer} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=2")
    assert Enum.map(Drafts.list_drafts(), & &1.id) == [newer.id, older.id]
  end

  test "paste_url creates a started draft" do
    assert {:ok, draft} = Drafts.paste_url(@url)
    assert draft.ebay_draft_id == "5345502780022"
    assert draft.state == "started"
    assert draft.title == nil
  end

  test "paste_url returns the existing draft" do
    assert {:ok, first} = Drafts.paste_url(@url)
    assert {:ok, second} = Drafts.paste_url("https://ebay.com/lstng?draft_id=5345502780022")
    assert first.id == second.id
    assert Repo.aggregate(Draft, :count) == 1
  end

  test "paste_url accepts draftId" do
    url =
      "https://www.ebay.com/lstng?draftId=5354106131923&mode=SellLikeItem&ReturnURL=https%3A%2F%2Fwww.ebay.com%2Fsh%2Flst%2Fdrafts"

    assert {:ok, draft} = Drafts.paste_url(url)
    assert draft.ebay_draft_id == "5354106131923"
    assert {:ok, again} = Drafts.paste_url("https://www.ebay.com/lstng?draft_id=5354106131923")
    assert again.id == draft.id
  end

  test "paste_url rejects a URL without draft_id" do
    assert {:error, changeset} = Drafts.paste_url("https://www.ebay.com/lstng?mode=SellLikeItem")
    assert %{url: [_]} = errors_on(changeset)
    assert Repo.aggregate(Draft, :count) == 0
  end

  test "paste_url rejects a non-eBay host" do
    assert {:error, changeset} = Drafts.paste_url("https://example.com/lstng?draft_id=123")
    assert %{url: [_]} = errors_on(changeset)
    assert Repo.aggregate(Draft, :count) == 0
  end
end
