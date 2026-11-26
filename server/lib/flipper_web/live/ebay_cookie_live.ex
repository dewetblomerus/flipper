defmodule FlipperWeb.EbayCookieLive do
  @moduledoc """
  Covers the page and asks for the eBay cookie while it is missing or rejected.
  """

  use FlipperWeb, :live_view

  alias Flipper.Drafts
  alias Flipper.Ebay.Session

  @impl true
  def render(assigns) do
    ~H"""
    <div
      :if={@status != :ok}
      id="ebay-cookie-popover"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ebay-cookie-title"
      class="fixed inset-0 z-40 flex overflow-y-auto bg-black/60 p-4 backdrop-blur-sm"
    >
      <.focus_wrap
        id="ebay-cookie-panel"
        class="m-auto w-full max-w-lg space-y-4 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-2xl"
      >
        <h2 id="ebay-cookie-title" class="text-lg font-semibold">{title(@status)}</h2>
        <.form for={@form} id="ebay-cookie-form" phx-submit="save">
          <.input
            field={@form[:value]}
            type="textarea"
            label="eBay cookie"
            rows="6"
            autocomplete="off"
            autofocus
            spellcheck="false"
            data-gramm="false"
            data-gramm_editor="false"
            data-enable-grammarly="false"
            phx-hook=".PasteTarget"
          />
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
        </.form>
      </.focus_wrap>
    </div>
    <.flash id="ebay-cookie-saved" kind={:info} flash={@flash} />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PasteTarget">
      // Keeps the field focused, so Ctrl+V lands in it without a click.
      export default {
        mounted() {
          this.focus = () => this.el.focus()
          window.addEventListener("focus", this.focus)
          // A blur with no next target is a click on something that takes no focus.
          this.el.addEventListener("blur", event => event.relatedTarget || setTimeout(this.focus))
          this.focus()
        },
        destroyed() {
          window.removeEventListener("focus", this.focus)
        },
      }
    </script>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Session.subscribe()

    {:ok,
     socket
     |> assign(:status, Session.status())
     |> assign(:form, cookie_form(""))}
  end

  @impl true
  def handle_event("save", %{"ebay_cookie" => %{"value" => value}}, socket) do
    case Session.set(value) do
      :ok ->
        Drafts.retry_failed()

        {:noreply,
         socket
         |> assign(:status, Session.status())
         |> assign(:form, cookie_form(""))
         |> put_flash(:info, "eBay cookie saved.")}

      {:error, "is blank"} ->
        {:noreply, assign(socket, :form, blank_cookie_form(value))}
    end
  end

  @impl true
  def handle_info(:ebay_session_changed, socket) do
    case Session.status() do
      :ok -> {:noreply, assign(socket, :status, :ok)}
      status -> {:noreply, socket |> clear_flash() |> assign(:status, status)}
    end
  end

  defp title(:missing), do: "Add your eBay cookie"
  defp title(:rejected), do: "eBay rejected the cookie"

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
