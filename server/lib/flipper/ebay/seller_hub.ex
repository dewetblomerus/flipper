defmodule Flipper.Ebay.SellerHub do
  @moduledoc """
  Lists the Seller Hub drafts, reads one, downloads and uploads photos, and saves a draft's
  first photo and field removals.
  """

  def drafts, do: impl().drafts()

  def fetch(ebay_draft_id), do: impl().fetch(ebay_draft_id)

  def download(url), do: impl().download(url)

  def upload_photo(ebay_draft_id, path, content_type) do
    impl().upload_photo(ebay_draft_id, path, content_type)
  end

  def update_draft(ebay_draft_id, changes), do: impl().update_draft(ebay_draft_id, changes)

  defp impl do
    Application.get_env(:flipper, :seller_hub, Flipper.Ebay.SellerHub.Client)
  end
end
