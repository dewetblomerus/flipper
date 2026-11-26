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
        <:item title="State">{@draft.state}</:item>
      </.list>

      <p :if={@refreshing or (@draft.state == "started" and is_nil(@draft.fetch_error))}>
        Fetching title and photos.
      </p>
      <p :if={@draft.fetch_error}>{@draft.fetch_error}</p>

      <div :if={ebay_status(@draft)} class="flex items-center gap-4">
        <p id="ebay-status">{ebay_status(@draft)}</p>
        <.button :if={retry_ebay?(@draft)} id="retry-ebay-photo" phx-click="retry_ebay_photo">
          Retry
        </.button>
        <.button :if={@draft.removal_error} id="retry-removals" phx-click="retry_removals">
          Retry
        </.button>
      </div>

      <section
        :if={@removals != []}
        id="field-removals"
        class="mb-8 space-y-3 rounded-xl border border-base-300 p-4"
      >
        <h2 class="text-lg font-semibold">{removals_title(@draft)}</h2>
        <p :if={reviewing?(@draft)} class="text-sm text-base-content/70">
          Approving removes the ticked fields from the eBay draft. Untick a field to keep it.
        </p>
        <.form
          for={@removal_form}
          id="field-removals-form"
          phx-change="select_removals"
          phx-submit="approve_removals"
        >
          <.input
            :for={{field, index} <- Enum.with_index(@removals)}
            type="checkbox"
            id={"removal-#{index}"}
            name={"remove[#{index}]"}
            label={"#{field.label}: #{field.value}"}
            checked={field.name in @selected}
            disabled={not reviewing?(@draft)}
          />
          <.button :if={reviewing?(@draft)} id="approve-removals" variant="primary">
            Approve removals
          </.button>
        </.form>
      </section>

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
     |> assign(:removal_form, to_form(%{}, as: :remove))
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
  def handle_event("retry_ebay_photo", _params, socket) do
    case Drafts.retry_ebay_photo(socket.assigns.draft) do
      {:ok, _photo} ->
        {:noreply, reload(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nothing to retry.")}
    end
  end

  @impl true
  def handle_event("retry_removals", _params, socket) do
    case Drafts.retry_removals(socket.assigns.draft) do
      {:ok, _draft} ->
        {:noreply, reload(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nothing to retry.")}
    end
  end

  @impl true
  def handle_event("select_removals", params, socket) do
    {:noreply, assign(socket, :selected, ticked(socket.assigns.removals, params))}
  end

  @impl true
  def handle_event("approve_removals", params, socket) do
    names = ticked(socket.assigns.removals, params)

    case Drafts.approve_field_removals(socket.assigns.draft, names) do
      {:ok, _draft} ->
        {:noreply, reload(socket)}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Those removals are already approved.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not approve the removals.")}
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

  defp approved?(draft), do: draft.state in @photo_locked

  defp reviewing?(draft), do: draft.state == "field_removals_drafted"

  defp removals_title(%{state: "finished"}), do: "Ticked fields were removed"
  defp removals_title(_draft), do: "Fields to remove"

  defp ebay_status(%{state: "photo_edits_approved", removal_error: error})
       when is_binary(error) do
    "Reading the eBay draft failed: #{error}"
  end

  defp ebay_status(%{state: "photo_edits_approved", photos: [%{use_edited: true} = first | _]}) do
    cond do
      first.replaced_on_ebay_at -> "Replaced on eBay."
      first.ebay_error -> "eBay replacement failed: #{first.ebay_error}"
      true -> "Replacing on eBay."
    end
  end

  defp ebay_status(%{state: "photo_edits_approved"}), do: "Reading the eBay draft."

  defp ebay_status(%{state: "field_removals_approved", removal_error: error})
       when is_binary(error) do
    "Removing fields failed: #{error}"
  end

  defp ebay_status(%{state: "field_removals_approved"}), do: "Removing fields on eBay."
  defp ebay_status(%{state: "finished"}), do: "eBay draft updated."
  defp ebay_status(_draft), do: nil

  defp assign_draft(socket, draft) do
    removals = removals(draft)

    socket
    |> assign(:selected, selected(socket.assigns, draft, removals))
    |> assign(:removals, removals)
    |> assign(:draft, draft)
  end

  defp reload(socket), do: assign_draft(socket, Drafts.get_draft!(socket.assigns.draft.id))

  defp removals(%{state: state} = draft)
       when state in ["field_removals_drafted", "field_removals_approved", "finished"] do
    Drafts.proposed_removals(draft)
  end

  defp removals(_draft), do: []

  # Every field starts ticked. A reload during the review keeps the person's ticks.
  defp selected(
         %{draft: %{state: "field_removals_drafted"}, selected: selected},
         %{state: "field_removals_drafted"},
         _removals
       ) do
    selected
  end

  defp selected(_assigns, %{state: "field_removals_drafted"}, removals) do
    Enum.map(removals, & &1.name)
  end

  defp selected(_assigns, draft, _removals), do: draft.approved_removals || []

  defp ticked(removals, params) do
    ticks = Map.get(params, "remove", %{})

    for {field, index} <- Enum.with_index(removals),
        ticks[to_string(index)] == "true",
        do: field.name
  end

  defp retry_ebay?(%{state: "photo_edits_approved", photos: [first | _]}) do
    first.use_edited == true and is_binary(first.ebay_error)
  end

  defp retry_ebay?(_draft), do: false

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
