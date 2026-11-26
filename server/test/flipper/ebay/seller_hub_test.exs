defmodule Flipper.Ebay.SellerHubTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.Client

  # The least a listing page holds to be read as a draft.
  @draft_page ~s({"title":{"value":"Vintage lamp"},"pictures":[],) <>
                ~s("TITLE":{"_type":"TitleViewHelix"},) <>
                ~s("ATTRIBUTES":{"_type":"AttributesViewHelix"}})

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
             "https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/aaa/$_57.JPG",
             "https://i.ebayimg.com/00/s/MTYwMFgxMjAw/z/bbb/$_57.JPG"
           ]
  end

  test "parse returns a title when the draft has no photos" do
    body = ~s({"title":{"value":"Bare item"},"pictures":[]})
    assert {:ok, %{title: "Bare item", photo_urls: []}} = Client.parse(body)
  end

  test "parse reads the custom label as the SKU" do
    assert {:ok, %{sku: "A-17"}} = Client.parse(listing_with_label(~s(" A-17 ")))
  end

  test "parse has no SKU while the custom label is empty or missing" do
    assert {:ok, %{sku: nil}} = Client.parse(listing_with_label(~s("")))
    assert {:ok, %{sku: nil}} = Client.parse(~s({"title":{"value":"Bare item"},"pictures":[]}))
  end

  test "parse fails when the page has neither a title nor photos" do
    assert {:error, "eBay draft had no title or photos"} = Client.parse("<html></html>")
  end

  test "fetch fails on a page without a draft's modules" do
    stub =
      stub_ebay(fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s({"title":{"value":"Vintage lamp"},"pictures":[]}))
      end)

    assert {:error, "eBay listing page had no draft"} =
             Client.fetch("1", cookie: "session", plug: stub)
  end

  test "fetch follows an eBay redirect" do
    stub =
      stub_ebay(fn conn ->
        if conn.query_string =~ "mode=AddItem" do
          Plug.Conn.send_resp(conn, 200, @draft_page)
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
        Plug.Conn.send_resp(conn, 200, @draft_page)
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

  @listing_page ~S"""
  <html>
    <script>
      window.model = {"epsData":{"s":"SuperSize","n":"i","v":"2","uaek":"640","uaes":"uaes-token","aXRequest":"2","wm":"","endpoint":"https://mach-100.ebay.com/ws/eBayISAPI.dll?EpsBasic","type":"POST"},
        "PHOTOS":{"_type":"PhotosViewHelix","photosInput":{"photos":[
          {"url":"https://i.ebayimg.com/00/s/aaa/z/one/$_1.JPG?set_id=8","thumbnail":"t1"},
          {"url":"https://i.ebayimg.com/00/s/aaa/z/two/$_1.JPG?set_id=8","thumbnail":"t2"}
        ]}}};
    </script>
  </html>
  """

  test "the listing page holds the upload fields and current photos" do
    assert {:ok, %{"uaes" => "uaes-token", "endpoint" => "https://mach-100" <> _}} =
             Client.eps_data(@listing_page)

    assert {:ok,
            [
              "https://i.ebayimg.com/00/s/aaa/z/one/$_1.JPG?set_id=8",
              "https://i.ebayimg.com/00/s/aaa/z/two/$_1.JPG?set_id=8"
            ]} = Client.draft_photos(@listing_page)
  end

  test "a page without them is an error" do
    assert {:error, _} = Client.eps_data("<html></html>")
    assert {:error, _} = Client.draft_photos("<html></html>")
  end

  test "the upload response holds the hosted photo url" do
    url = "https://i.ebayimg.com/00/s/aaa/z/new/$_1.PNG?set_id=8"
    assert {:ok, ^url} = Client.uploaded_url("VERSION:2;" <> url)
    assert {:error, _} = Client.uploaded_url("VERSION:2;https://example.com/x.png")
    assert {:error, _} = Client.uploaded_url("ERROR")
  end

  defp listing_with_label(value) do
    ~s({"TITLE":{"_type":"TitleViewHelix",) <>
      ~s("titleField":{"name":"title","value":"Vintage lamp"},) <>
      ~s("customLabelField":{"name":"customLabel","value":#{value}}}})
  end
end
