defmodule FlipperWeb.AutoLive do
  @moduledoc """
  Shows one pending decision at a time as its draft's page.
  """

  use FlipperWeb, :live_view

  alias Flipper.Drafts
  alias Flipper.Drafts.Decision

  # A view per decision keeps clicks and form state from reaching the next one.
  @impl true
  def render(assigns) do
    ~H"""
    <%= if @decision do %>
      {live_render(@socket, FlipperWeb.DraftLive.Show,
        id: "auto-#{@decision.kind}-#{@decision.draft_id}",
        session: %{"id" => @decision.draft_id}
      )}
    <% else %>
      <Layouts.app flash={@flash}>
        <div id="auto-empty">
          <.header>
            Nothing to decide
            <:actions>
              <.button navigate={~p"/drafts"}>Drafts</.button>
            </:actions>
          </.header>
        </div>
      </Layouts.app>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Drafts.subscribe()

    {:ok, advance(assign(socket, page_title: "Auto", decision: nil))}
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:draft_fetched, :draft_changed] do
    {:noreply, advance(socket)}
  end

  # Keeps the shown decision while it is pending.
  defp advance(socket) do
    pending = Decision.pending()

    if socket.assigns.decision in pending do
      socket
    else
      assign(socket, :decision, List.first(pending))
    end
  end
end
