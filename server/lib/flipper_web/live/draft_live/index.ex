defmodule FlipperWeb.DraftLive.Index do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="max-w-4xl">
      <.header>
        Listing Drafts
        <:actions>
          <.button id="refresh-drafts" phx-click="refresh_drafts" disabled={@refreshing}>
            <.icon
              name="hero-arrow-path"
              class={["size-5", @refreshing && "motion-safe:animate-spin"]}
            />
            {if @refreshing, do: "Refreshing", else: "Refresh Drafts"}
          </.button>
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
        <:col :let={{_id, draft}} label="">
          <img
            :if={photo = first_photo(draft)}
            src={~p"/photos/#{photo}"}
            alt=""
            class="size-12 rounded object-cover"
          />
        </:col>
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
    if connected?(socket) do
      Drafts.subscribe()
      Drafts.subscribe_import()
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Drafts")
     |> assign(:refreshing, false)
     |> stream(:drafts, list_drafts())}
  end

  @impl true
  def handle_event("refresh_drafts", _params, socket) do
    case Drafts.refresh_list() do
      {:ok, _job} ->
        {:noreply, socket |> clear_flash() |> assign(:refreshing, true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Refresh failed.")}
    end
  end

  @impl true
  def handle_info({:drafts_import, result}, socket) do
    {:noreply, socket |> report(result) |> reload()}
  end

  def handle_info({event, _id}, socket) when event in [:draft_fetched, :draft_changed] do
    {:noreply, reload(socket)}
  end

  # Only a page that asked for a refresh reports how it went.
  defp report(%{assigns: %{refreshing: false}} = socket, _result), do: socket

  defp report(socket, result) do
    socket = assign(socket, :refreshing, false)

    case result do
      :ok -> put_flash(socket, :info, "Drafts refreshed.")
      {_failed, reason} -> put_flash(socket, :error, "Refresh failed: #{reason}")
    end
  end

  defp reload(socket), do: stream(socket, :drafts, list_drafts(), reset: true)

  defp list_drafts do
    Drafts.list_drafts()
  end

  defp first_photo(%{photos: [photo | _]}), do: photo
  defp first_photo(_draft), do: nil
end
