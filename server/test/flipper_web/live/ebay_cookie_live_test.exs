defmodule FlipperWeb.EbayCookieLiveTest do
  use FlipperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Flipper.Ebay.Session

  setup do
    path = Application.fetch_env!(:flipper, :ebay_cookie_path)
    previous = Application.get_env(:flipper, :ebay_cookie)
    File.rm(path)
    Application.put_env(:flipper, :ebay_cookie, nil)
    Session.load()

    on_exit(fn ->
      File.rm(path)

      if is_binary(previous) and previous != "" do
        Application.put_env(:flipper, :ebay_cookie, previous)
      else
        Application.delete_env(:flipper, :ebay_cookie)
      end

      Session.load()
    end)

    :ok
  end

  test "asks for the cookie, saves it, and replaces it empty", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "eBay cookie"
    refute html =~ "eBay session is saved."

    html =
      view
      |> form("#ebay-cookie-form", ebay_cookie: %{value: "   "})
      |> render_submit()

    assert html =~ "is blank"
    assert is_nil(Session.cookie())

    html =
      view
      |> form("#ebay-cookie-form", ebay_cookie: %{value: "cookie: secret-value"})
      |> render_submit()

    assert html =~ "eBay cookie saved."
    assert html =~ "eBay session is saved."
    refute html =~ "secret-value"
    assert Session.cookie() == "secret-value"

    html = view |> element("#replace-cookie", "Replace") |> render_click()
    assert html =~ "eBay cookie"
    refute html =~ "secret-value"

    assert view |> element("textarea") |> render() =~ "></textarea>"
  end
end
