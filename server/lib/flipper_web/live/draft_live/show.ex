defmodule FlipperWeb.DraftLive.Show do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="max-w-5xl">
      <.header>
        Draft {@draft.id}
        <:actions>
          <.button :if={@draft.photos == []} id="refresh-draft" phx-click="refresh" variant="primary">
            Refresh
          </.button>
          <.button :if={redo_edit?(@draft)} id="redo-edits" phx-click="redo_edits">
            Redo edit
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

      <p
        :if={@refreshing or (@draft.state == "started" and is_nil(@draft.fetch_error))}
        id="draft-fetch-status"
      >
        Fetching title and photos.
      </p>
      <p :if={@draft.fetch_error}>{@draft.fetch_error}</p>

      <div :if={ebay_status(@draft)} class="flex items-center gap-4">
        <p id="ebay-photo-status">{ebay_status(@draft)}</p>
        <.button :if={retry_ebay?(@draft)} id="retry-ebay-photo" phx-click="retry_ebay_photo">
          Retry
        </.button>
      </div>

      <ul :if={@draft.photos != []} id="draft-photos" class="space-y-8">
        <li
          :for={photo <- @draft.photos}
          id={"photo-#{photo.id}"}
          class={[first_photo?(@draft, photo) && "grid grid-cols-2 gap-4"]}
        >
          <%= if first_photo?(@draft, photo) && photo.edited_path do %>
            <button
              type="button"
              id={"photo-#{photo.id}-original"}
              phx-click="choose_edit"
              phx-value-id={photo.id}
              phx-value-use_edited="false"
              aria-pressed={to_string(photo.use_edited == false)}
              disabled={approved?(@draft)}
              class={[
                "rounded-xl border border-base-300 p-2 text-left transition enabled:hover:border-primary",
                photo.use_edited == false && "ring-2 ring-primary"
              ]}
            >
              <img
                src={~p"/photos/#{photo}"}
                alt={"Original #{photo.position}"}
                class="aspect-square w-full rounded-lg bg-base-200 object-contain"
              />
              <span class="mt-2 block text-sm">Original</span>
            </button>
            <button
              type="button"
              id={"photo-#{photo.id}-edited"}
              phx-click="choose_edit"
              phx-value-id={photo.id}
              phx-value-use_edited="true"
              aria-pressed={to_string(photo.use_edited == true)}
              disabled={approved?(@draft)}
              class={[
                "rounded-xl border border-base-300 p-2 text-left transition enabled:hover:border-primary",
                photo.use_edited == true && "ring-2 ring-primary"
              ]}
            >
              <img
                src={~p"/photos/#{photo}/edited"}
                alt={"Edited #{photo.position}"}
                class="aspect-square w-full rounded-lg bg-base-200 object-contain"
              />
              <span class="mt-2 block text-sm">Edited</span>
            </button>
          <% else %>
            <%= if first_photo?(@draft, photo) do %>
              <div id={"photo-#{photo.id}-original"}>
                <img
                  src={~p"/photos/#{photo}"}
                  alt={"Original #{photo.position}"}
                  class="aspect-square w-full rounded-lg bg-base-200 object-contain"
                />
                <span class="mt-2 block text-sm">Original</span>
              </div>
              <div
                id={"photo-#{photo.id}-edited"}
                class="flex items-center justify-center gap-2 rounded-xl border border-dashed border-base-300"
              >
                <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
                <span class="text-sm">Editing</span>
              </div>
            <% else %>
              <img
                src={~p"/photos/#{photo}"}
                alt={"Photo #{photo.position}"}
                class="w-full max-w-md rounded-lg"
              />
            <% end %>
          <% end %>
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
  def handle_event("redo_edits", _params, socket) do
    case Drafts.redo_edits(socket.assigns.draft) do
      {:ok, draft} ->
        {:noreply, assign(socket, :draft, Drafts.get_draft!(draft.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not redo the edit.")}
    end
  end

  @impl true
  def handle_event("retry_ebay_photo", _params, socket) do
    case Drafts.retry_ebay_photo(socket.assigns.draft) do
      {:ok, _photo} ->
        {:noreply, assign(socket, :draft, Drafts.get_draft!(socket.assigns.draft.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nothing to retry.")}
    end
  end

  @impl true
  def handle_event("choose_edit", %{"id" => id, "use_edited" => choice}, socket)
      when choice in ["true", "false"] do
    draft = socket.assigns.draft

    case Enum.find(draft.photos, &(to_string(&1.id) == id)) do
      nil -> {:noreply, put_flash(socket, :error, "Photo not found.")}
      photo -> save_choice(socket, draft, photo, choice == "true")
    end
  end

  defp first_photo?(%{photos: [first | _]}, photo), do: photo.id == first.id
  defp first_photo?(_draft, _photo), do: false

  defp redo_edit?(%{photos: [first | _]} = draft) do
    is_binary(first.edited_path) and not approved?(draft)
  end

  defp redo_edit?(_draft), do: false

  defp approved?(draft), do: draft.state == "photo_edits_approved"

  defp ebay_status(%{state: "photo_edits_approved", photos: [%{use_edited: true} = first | _]}) do
    cond do
      first.replaced_on_ebay_at -> "Replaced on eBay."
      first.ebay_error -> "eBay replacement failed: #{first.ebay_error}"
      true -> "Replacing on eBay."
    end
  end

  defp ebay_status(_draft), do: nil

  defp retry_ebay?(%{state: "photo_edits_approved", photos: [first | _]}) do
    first.use_edited == true and is_binary(first.ebay_error)
  end

  defp retry_ebay?(_draft), do: false

  defp save_choice(socket, draft, photo, use_edited) do
    case Drafts.choose_edit(photo, use_edited) do
      {:ok, _photo} ->
        {:noreply, assign(socket, :draft, Drafts.get_draft!(draft.id))}

      {:error, :not_edited} ->
        {:noreply, put_flash(socket, :error, "That photo is still editing.")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "That choice is already approved.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save the choice.")}
    end
  end

  @impl true
  def handle_info({:draft_changed, _id}, socket) do
    {:noreply, assign(socket, :draft, Drafts.get_draft!(socket.assigns.draft.id))}
  end

  def handle_info({:draft_fetched, _id}, socket) do
    {:noreply,
     socket
     |> assign(:refreshing, false)
     |> assign(:draft, Drafts.get_draft!(socket.assigns.draft.id))}
  end
end
