defmodule FlipperWeb.DraftLive.Form do
  use FlipperWeb, :live_view

  alias Flipper.Drafts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="draft-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:url]} type="text" label="eBay draft URL" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Create draft</.button>
          <.button navigate={~p"/drafts"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Paste a draft URL")
     |> assign(:form, to_form(%{"url" => ""}, as: :draft))}
  end

  @impl true
  def handle_event("validate", %{"draft" => %{"url" => url}}, socket) do
    {:noreply, assign(socket, form: to_form(Drafts.change_url(url), as: :draft))}
  end

  def handle_event("save", %{"draft" => %{"url" => url}}, socket) do
    case Drafts.paste_url(url) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: ~p"/drafts/#{draft}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :draft))}
    end
  end
end
