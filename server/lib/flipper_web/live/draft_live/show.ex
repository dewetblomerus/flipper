defmodule FlipperWeb.DraftLive.Show do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Draft {@draft.id}
        <:actions>
          <.button navigate={~p"/drafts"}>
            <.icon name="hero-arrow-left" />
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Ebay draft">{@draft.ebay_draft_id}</:item>
        <:item title="Title">{@draft.title}</:item>
        <:item title="State">{@draft.state}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Draft")
     |> assign(:draft, Drafts.get_draft!(id))}
  end
end
