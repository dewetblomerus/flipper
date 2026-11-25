defmodule Flipper.Ebay.SellerHub do
  @moduledoc """
  Fetches a Seller Hub draft, downloads its photos, and replaces its first photo.
  """

  def fetch(ebay_draft_id), do: impl().fetch(ebay_draft_id)

  def download(url), do: impl().download(url)

  def upload_photo(ebay_draft_id, path, content_type) do
    impl().upload_photo(ebay_draft_id, path, content_type)
  end

  def set_first_photo(ebay_draft_id, url), do: impl().set_first_photo(ebay_draft_id, url)

  defp impl do
    Application.get_env(:flipper, :seller_hub, Flipper.Ebay.SellerHub.Client)
  end
end
