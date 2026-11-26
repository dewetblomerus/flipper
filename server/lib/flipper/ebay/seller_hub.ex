defmodule Flipper.Ebay.SellerHub do
  @moduledoc """
  Reads a Seller Hub draft, downloads its photos, replaces its first photo, and removes
  optional fields.
  """

  def fetch(ebay_draft_id), do: impl().fetch(ebay_draft_id)

  def download(url), do: impl().download(url)

  def upload_photo(ebay_draft_id, path, content_type) do
    impl().upload_photo(ebay_draft_id, path, content_type)
  end

  def set_first_photo(ebay_draft_id, url), do: impl().set_first_photo(ebay_draft_id, url)

  def read_draft(ebay_draft_id), do: impl().read_draft(ebay_draft_id)

  def remove_fields(ebay_draft_id, names), do: impl().remove_fields(ebay_draft_id, names)

  defp impl do
    Application.get_env(:flipper, :seller_hub, Flipper.Ebay.SellerHub.Client)
  end
end
