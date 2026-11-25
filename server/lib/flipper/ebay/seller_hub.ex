defmodule Flipper.Ebay.SellerHub do
  def fetch(ebay_draft_id), do: impl().fetch(ebay_draft_id)

  def download(url), do: impl().download(url)

  defp impl do
    Application.get_env(:flipper, :seller_hub, Flipper.Ebay.SellerHub.Client)
  end
end
