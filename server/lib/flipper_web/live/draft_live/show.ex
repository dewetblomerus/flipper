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
          <.button :if={@draft.photos == []} id="refresh-draft" phx-click="refresh" variant="primary">
            Refresh
          </.button>
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

      <p :if={@refreshing or (@draft.state == "started" and is_nil(@draft.fetch_error))}>
        Fetching title and photos.
      </p>
      <p :if={@draft.fetch_error}>{@draft.fetch_error}</p>

      <ul :if={@draft.photos != []} class="space-y-4">
        <li :for={photo <- @draft.photos}>
          <img src={~p"/photos/#{photo}"} alt={"Photo #{photo.position}"} class="w-full" />
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    draft = Drafts.get_draft!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Flipper.PubSub, "draft:#{draft.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Draft")
     |> assign(:refreshing, false)
     |> assign(:draft, draft)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    case Drafts.refresh(socket.assigns.draft) do
      {:ok, draft} ->
        draft = Drafts.get_draft!(draft.id)

        {:noreply,
         socket
         |> assign(:refreshing, draft.photos == [])
         |> assign(:draft, draft)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Refresh failed.")}
    end
  end

  @impl true
  def handle_info({:draft_fetched, _id}, socket) do
    {:noreply,
     socket
     |> assign(:refreshing, false)
     |> assign(:draft, Drafts.get_draft!(socket.assigns.draft.id))}
  end
end
