defmodule FlipperWeb.DraftLive do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("save", %{"draft" => %{"url" => url}}, socket) do
    case Drafts.paste_url(url) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: ~p"/drafts/#{draft}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :draft))}
    end
  end

  @impl true
  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">Paste a draft URL</h1>
      <.form for={@form} id="draft-form" phx-submit="save" class="space-y-4">
        <.input field={@form[:url]} type="text" label="eBay draft URL" />
        <.button>Create draft</.button>
      </.form>
      <.button navigate={~p"/drafts"}>Drafts</.button>
    </Layouts.app>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">Drafts</h1>
      <ul id="drafts" class="space-y-2">
        <li :for={draft <- @drafts}>
          <.link id={"draft-#{draft.id}"} navigate={~p"/drafts/#{draft}"} class="block">
            <span>{draft.ebay_draft_id}</span>
            <span class="text-sm text-base-content/70">{draft.state}</span>
          </.link>
        </li>
      </ul>
      <p :if={@drafts == []} id="drafts-empty">No drafts yet.</p>
      <.button navigate={~p"/"}>Paste a URL</.button>
    </Layouts.app>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">Draft</h1>
      <dl class="space-y-2">
        <div>
          <dt class="text-sm text-base-content/70">Id</dt>
          <dd id="draft-id">{@draft.id}</dd>
        </div>
        <div>
          <dt class="text-sm text-base-content/70">eBay draft id</dt>
          <dd id="ebay-draft-id">{@draft.ebay_draft_id}</dd>
        </div>
        <div>
          <dt class="text-sm text-base-content/70">State</dt>
          <dd id="draft-state">{@draft.state}</dd>
        </div>
      </dl>
      <div class="flex gap-2">
        <.button navigate={~p"/drafts"}>Drafts</.button>
        <.button navigate={~p"/"}>Paste another URL</.button>
      </div>
    </Layouts.app>
    """
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: "Drafts", drafts: Drafts.list_drafts())
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "Paste a draft URL", form: to_form(%{"url" => ""}, as: :draft))
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(page_title: "Draft", draft: Drafts.get_draft!(id))
  end
end
