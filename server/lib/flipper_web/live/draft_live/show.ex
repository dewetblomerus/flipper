defmodule FlipperWeb.DraftLive.Show do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  # The photo pick is locked from its approval on.
  @photo_locked ~w(photo_edits_approved field_removals_drafted field_removals_approved finished)

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
        <:item title="Custom label (SKU)">{@draft.sku}</:item>
        <:item title="State">{@draft.state}</:item>
      </.list>

      <p :if={@refreshing or (@draft.state == "started" and is_nil(@draft.fetch_error))}>
        Fetching title and photos.
      </p>
      <p :if={@draft.fetch_error}>{@draft.fetch_error}</p>

      <div :if={ebay_status(@draft)} class="flex items-center gap-4">
        <p id="ebay-status">{ebay_status(@draft)}</p>
        <.button :if={@draft.ebay_error} id="retry-ebay" phx-click="retry_ebay">
          Retry
        </.button>
      </div>

      <div
        :for={photo <- Enum.take(@draft.photos, 1)}
        id={"photo-#{photo.id}"}
        class="grid grid-cols-2 gap-4"
      >
        <%= if photo.edited_path do %>
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
        <% end %>
      </div>

      <section
        :if={@draft.photos != [] and @removals != []}
        id="field-removals"
        class="mt-8 space-y-3 rounded-xl border border-base-300 p-4"
      >
        <h2 class="text-lg font-semibold">{removals_title(@draft)}</h2>
        <p :if={not approved?(@draft)} class="text-sm text-base-content/70">
          Picking a photo also removes these fields from the eBay draft.
        </p>
        <ul class="list-disc space-y-1 pl-5 text-sm">
          <li :for={field <- @removals}>{field.label}: {field.value}</li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(:not_mounted_at_router, session, socket), do: mount(session, session, socket)

  def mount(%{"id" => id}, _session, socket) do
    draft = Drafts.get_draft!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Flipper.PubSub, "draft:#{draft.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Draft")
     |> assign(:refreshing, false)
     |> assign_draft(draft)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    case Drafts.refresh(socket.assigns.draft) do
      {:ok, draft} ->
        draft = Drafts.get_draft!(draft.id)

        {:noreply,
         socket
         |> assign(:refreshing, draft.photos == [])
         |> assign_draft(draft)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Refresh failed.")}
    end
  end

  @impl true
  def handle_event("redo_edits", _params, socket) do
    case Drafts.redo_edits(socket.assigns.draft) do
      {:ok, draft} ->
        {:noreply, assign_draft(socket, Drafts.get_draft!(draft.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not redo the edit.")}
    end
  end

  @impl true
  def handle_event("retry_ebay", _params, socket) do
    case Drafts.retry_ebay(socket.assigns.draft) do
      {:ok, _draft} ->
        {:noreply, reload(socket)}

      {:error, :job_already_queued} ->
        {:noreply, put_flash(socket, :error, "The last attempt is still finishing. Try again.")}

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

  defp redo_edit?(%{photos: [first | _]} = draft) do
    is_binary(first.edited_path) and not approved?(draft)
  end

  defp redo_edit?(_draft), do: false

  defp approved?(draft), do: draft.state in @photo_locked

  defp removals_title(%{state: "finished"}), do: "Removed fields"
  defp removals_title(_draft), do: "Fields to remove"

  defp ebay_status(%{state: "field_removals_approved", ebay_error: error})
       when is_binary(error) do
    "Updating eBay failed: #{error}"
  end

  defp ebay_status(%{state: "field_removals_approved"}), do: "Updating the eBay draft."
  defp ebay_status(%{state: "finished"}), do: "eBay draft updated."
  defp ebay_status(_draft), do: nil

  defp assign_draft(socket, draft) do
    socket
    |> assign(:removals, removals(draft))
    |> assign(:draft, draft)
  end

  defp reload(socket), do: assign_draft(socket, Drafts.get_draft!(socket.assigns.draft.id))

  # Once the removals are approved, only those are listed.
  defp removals(%{approved_removals: nil} = draft), do: Drafts.proposed_removals(draft)

  defp removals(draft) do
    Enum.filter(Drafts.proposed_removals(draft), &(&1.name in draft.approved_removals))
  end

  defp save_choice(socket, draft, photo, use_edited) do
    case Drafts.choose_edit(photo, use_edited) do
      {:ok, _photo} ->
        {:noreply, assign_draft(socket, Drafts.get_draft!(draft.id))}

      {:error, :not_edited} ->
        {:noreply, put_flash(socket, :error, "That photo is still editing.")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "That choice is already approved.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save the choice.")}
    end
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:draft_fetched, :draft_changed] do
    {:noreply,
     socket
     |> assign(:refreshing, false)
     |> reload()}
  end
end
