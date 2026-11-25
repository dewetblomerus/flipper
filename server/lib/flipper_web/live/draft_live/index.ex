defmodule FlipperWeb.DraftLive.Index do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Drafts
        <:actions>
          <.button variant="primary" navigate={~p"/drafts/new"}>
            <.icon name="hero-plus" /> Paste a URL
          </.button>
        </:actions>
      </.header>

      <.table
        id="drafts"
        rows={@streams.drafts}
        row_click={fn {_id, draft} -> JS.navigate(~p"/drafts/#{draft}") end}
      >
        <:col :let={{_id, draft}} label="Ebay draft">{draft.ebay_draft_id}</:col>
        <:col :let={{_id, draft}} label="Title">{draft.title}</:col>
        <:col :let={{_id, draft}} label="State">{draft.state}</:col>
        <:action :let={{_id, draft}}>
          <div class="sr-only">
            <.link navigate={~p"/drafts/#{draft}"}>Show</.link>
          </div>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Drafts")
     |> stream(:drafts, list_drafts())}
  end

  defp list_drafts() do
    Drafts.list_drafts()
  end
end
