defmodule FlipperWeb.DraftLive.Index do
  use FlipperWeb, :live_view

  alias Flipper.Drafts
  alias Flipper.Ebay.Session

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width="max-w-4xl">
      <.header>
        Listing Drafts
        <:actions>
          <.button variant="primary" navigate={~p"/drafts/new"}>
            <.icon name="hero-plus" /> Paste a URL
          </.button>
        </:actions>
      </.header>

      <div id="ebay-cookie">
        <p :if={@cookie_saved and not @replacing_cookie}>eBay session is saved.</p>
        <.button
          :if={@cookie_saved and not @replacing_cookie}
          id="replace-cookie"
          phx-click="replace_cookie"
        >
          Replace
        </.button>
        <.form
          :if={not @cookie_saved or @replacing_cookie}
          for={@cookie_form}
          id="ebay-cookie-form"
          phx-submit="save_cookie"
        >
          <.input field={@cookie_form[:value]} type="textarea" label="eBay cookie" />
          <.button variant="primary">Save</.button>
        </.form>
      </div>

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
    {:ok,
     socket
     |> assign(:page_title, "Listing Drafts")
     |> assign(:cookie_saved, cookie_saved?())
     |> assign(:replacing_cookie, false)
     |> assign(:cookie_form, cookie_form(""))
     |> stream(:drafts, list_drafts())}
  end

  @impl true
  def handle_event("replace_cookie", _params, socket) do
    {:noreply,
     socket
     |> assign(:replacing_cookie, true)
     |> assign(:cookie_form, cookie_form(""))}
  end

  def handle_event("save_cookie", %{"ebay_cookie" => %{"value" => value}}, socket) do
    case Session.set(value) do
      :ok ->
        {:noreply,
         socket
         |> assign(:cookie_saved, true)
         |> assign(:replacing_cookie, false)
         |> assign(:cookie_form, cookie_form(""))
         |> put_flash(:info, "eBay cookie saved.")}

      {:error, "is blank"} ->
        {:noreply, assign(socket, :cookie_form, blank_cookie_form(value))}
    end
  end

  defp list_drafts do
    Drafts.list_drafts()
  end

  defp first_photo(%{photos: [photo | _]}), do: photo
  defp first_photo(_draft), do: nil

  defp cookie_saved? do
    is_binary(Session.cookie())
  end

  defp cookie_form(value) do
    to_form(%{"value" => value}, as: :ebay_cookie)
  end

  defp blank_cookie_form(value) do
    changeset =
      {%{}, %{value: :string}}
      |> Ecto.Changeset.cast(%{"value" => value}, [:value])
      |> Ecto.Changeset.add_error(:value, "is blank")
      |> Map.put(:action, :insert)

    to_form(changeset, as: :ebay_cookie)
  end
end
