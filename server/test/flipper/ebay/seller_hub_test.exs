defmodule Flipper.Ebay.SellerHubTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.Client

  test "parse reads the title and full-size photo urls" do
    body = """
    <html>
      <script type="application/json">
        {"title":"Vintage lamp","pictures":[
          {"url":"https://i.ebayimg.com/images/g/abc/s-l500.jpg"},
          {"url":"https://i.ebayimg.com/images/g/abc/s-l1600.jpg?set_id=1"},
          {"url":"https://i.ebayimg.com/images/g/def/s-l960.webp"}
        ]}
      </script>
    </html>
    """

    assert {:ok, %{title: "Vintage lamp", photo_urls: urls}} = Client.parse(body)

    assert urls == [
             "https://i.ebayimg.com/images/g/abc/s-l1600.jpg",
             "https://i.ebayimg.com/images/g/def/s-l1600.webp"
           ]
  end

  test "parse reads a Seller Hub title and full-size photos" do
    body = """
    {"title":"Lamp+with+shade","titleField":{"name":"title","value":"Lamp with shade"},"pictures":[
      {"url":"https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/aaa/$_26.JPG?set_id=1","thumbnail":"https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/aaa/$_26.JPG"},
      {"url":"https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/bbb/$_1.JPG","thumbnail":"https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/bbb/$_1.JPG"}
    ]}
    """

    assert {:ok, %{title: "Lamp with shade", photo_urls: urls}} = Client.parse(body)

    assert urls == [
             "https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/aaa/$_1.JPG",
             "https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/bbb/$_1.JPG"
           ]
  end

  test "parse returns a title when the draft has no photos" do
    body = ~s({"title":{"value":"Bare item"},"pictures":[]})
    assert {:ok, %{title: "Bare item", photo_urls: []}} = Client.parse(body)
  end

  test "parse fails when the page has neither a title nor photos" do
    assert {:error, "eBay draft had no title or photos"} = Client.parse("<html></html>")
  end

  test "fetch follows an eBay redirect" do
    stub =
      stub_ebay(fn conn ->
        if conn.query_string =~ "mode=AddItem" do
          Plug.Conn.send_resp(conn, 200, ~s({"title":{"value":"Vintage lamp"},"pictures":[]}))
        else
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://www.ebay.com/lstng?draftId=1&mode=AddItem"
          )
          |> Plug.Conn.send_resp(307, "")
        end
      end)

    assert {:ok, %{title: "Vintage lamp", photo_urls: []}} =
             Client.fetch("1", cookie: "session", plug: stub)
  end

  test "fetch sends the cookie as a browser document request" do
    parent = self()

    stub =
      stub_ebay(fn conn ->
        send(parent, {:headers, conn.req_headers})
        Plug.Conn.send_resp(conn, 200, ~s({"title":{"value":"Vintage lamp"},"pictures":[]}))
      end)

    assert {:ok, %{title: "Vintage lamp"}} =
             Client.fetch("1", cookie: "session", plug: stub)

    assert_receive {:headers, headers}
    assert {"cookie", "session"} = List.keyfind(headers, "cookie", 0)
    assert {"referer", "https://www.ebay.com/sh/lst/drafts"} = List.keyfind(headers, "referer", 0)
    assert {"user-agent", user_agent} = List.keyfind(headers, "user-agent", 0)
    assert user_agent =~ "Chrome/"
  end

  test "fetch stops when eBay redirects to sign-in" do
    stub =
      stub_ebay(fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "location",
          "https://signin.ebay.com/ws/eBayISAPI.dll?SignIn"
        )
        |> Plug.Conn.send_resp(307, "")
      end)

    assert {:error, "eBay session is not signed in"} =
             Client.fetch("1", cookie: "session", plug: stub)
  end

  test "fetch reports an eBay browser check" do
    parent = self()

    stub =
      stub_ebay(fn conn ->
        send(parent, :hit)

        conn
        |> Plug.Conn.put_resp_header("location", "https://www.ebay.com/splashui/challenge?ap=1")
        |> Plug.Conn.send_resp(307, "")
      end)

    assert {:error, "eBay asked for a browser check"} =
             Client.fetch("1", cookie: "session", plug: stub)

    assert_received :hit
    refute_received :hit
  end

  test "fetch does not follow a redirect off eBay" do
    stub =
      stub_ebay(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://example.com/draft")
        |> Plug.Conn.send_resp(307, "")
      end)

    assert {:error, "eBay returned 307 to example.com"} =
             Client.fetch("1", cookie: "session", plug: stub)
  end

  defp stub_ebay(plug) do
    name = {:ebay, self(), System.unique_integer([:positive])}
    Req.Test.stub(name, plug)
    {Req.Test, name}
  end

  test "fetch without a cookie fails" do
    assert {:error, "eBay cookie is not set"} = Client.fetch("1", cookie: nil)
  end
end
