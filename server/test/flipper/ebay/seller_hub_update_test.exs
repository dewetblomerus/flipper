defmodule Flipper.Ebay.SellerHubUpdateTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.Client

  @tokens ~S|<div data-srt="{&quot;/lstng/api/listing_draft/:draftId(\\d+)/skip_validation&quot;:&quot;photo-token&quot;,&quot;/lstng/api/listing_draft/:draftId(\\d+)&quot;:&quot;draft-token&quot;}"></div>|
  @new_url "https://i.ebayimg.com/new.jpg"

  test "the main route's token is read" do
    assert {:ok, "draft-token"} = Client.draft_token(@tokens)
    assert {:error, _} = Client.draft_token("<html></html>")
  end

  test "fetch returns every data module without upload tokens" do
    server = draft_server([page(color: "Black")])

    assert {:ok, %{modules: modules}} = Client.fetch("123", cookie: "session", plug: server)

    assert Map.keys(modules) == ["ATTRIBUTES", "PHOTOS", "TITLE"]
    assert modules["TITLE"]["_type"] == "TitleViewHelix"

    assert modules["PHOTOS"] == %{
             "_type" => "PhotosViewHelix",
             "photosInput" => %{
               "photos" => [
                 %{"url" => "https://i.ebayimg.com/one.jpg"},
                 %{"url" => "https://i.ebayimg.com/two.jpg"}
               ]
             }
           }
  end

  test "update_draft saves the photo and removals in one request, and reads the draft back" do
    server = draft_server([page(color: "Black"), page(color: nil)])

    assert :ok = update(server, @new_url, ["attributes.Color"])

    assert_received {:put, "/lstng/api/listing_draft/123", ["draft-token"], body}
    assert body["pictures"] == [@new_url, "https://i.ebayimg.com/two.jpg"]
    assert body["attributes"] == %{"Color" => []}
    assert body["removedFields"] == []
    assert is_binary(body["requestId"])
    assert is_integer(body["requestMeta"]["lastDeltaTimestamp"])
    refute_received {:put, _, _, _}
    assert gets() == 2
  end

  test "update_draft without a photo leaves the photos alone" do
    server = draft_server([page(color: "Black"), page(color: nil)])

    assert :ok = update(server, nil, ["attributes.Color"])

    assert_received {:put, _, _, body}
    assert body["attributes"] == %{"Color" => []}
    refute Map.has_key?(body, "pictures")
  end

  test "update_draft saves a photo alone without reading the draft back" do
    server = draft_server([page(color: "Black")])

    assert :ok = update(server, @new_url, [])

    assert_received {:put, _, _, body}
    assert [@new_url, _] = body["pictures"]
    refute Map.has_key?(body, "attributes")
    assert gets() == 1
  end

  test "update_draft fails when eBay keeps a field" do
    server = draft_server([page(color: "Black")])

    assert {:error, "eBay draft kept Color"} = update(server, nil, ["attributes.Color"])
  end

  test "update_draft fails when a kept field is no longer optional" do
    for changed <- [[groups: ["REQUIRED"]], [read_only: true]] do
      server = draft_server([page(color: "Black"), page([color: "Black"] ++ changed)])

      assert {:error, "eBay draft kept Color"} = update(server, nil, ["attributes.Color"])
    end
  end

  test "update_draft with nothing to change makes no request" do
    assert :ok = Client.update_draft("123", %{photo: nil, remove: []}, cookie: nil)
  end

  defp update(server, photo, names) do
    changes = %{photo: photo, remove: names}
    Client.update_draft("123", changes, cookie: "session", plug: server)
  end

  defp gets(count \\ 0) do
    receive do
      :get -> gets(count + 1)
    after
      0 -> count
    end
  end

  # Serves the pages in order, repeating the last, and reports each request.
  defp draft_server(pages) do
    parent = self()
    agent = start_supervised!({Agent, fn -> pages end}, id: make_ref())
    name = {:ebay, self(), System.unique_integer([:positive])}

    Req.Test.stub(name, fn
      %{method: "GET"} = conn ->
        send(parent, :get)
        Plug.Conn.send_resp(conn, 200, Agent.get_and_update(agent, &next_page/1))

      %{method: "PUT"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        srt = Plug.Conn.get_req_header(conn, "srt")
        send(parent, {:put, conn.request_path, srt, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 200, "{}")
    end)

    {Req.Test, name}
  end

  defp next_page([page]), do: {page, [page]}
  defp next_page([page | rest]), do: {page, rest}

  defp page(opts) do
    specifics =
      Jason.encode!([
        %{
          name: "attributes.Color",
          groups: Keyword.get(opts, :groups, ["RECOMMENDED"]),
          readOnly: Keyword.get(opts, :read_only, false),
          value: List.wrap(opts[:color])
        }
      ])

    """
    <html>
      #{@tokens}
      <script>
        window.model = {"TITLE":{"_type":"TextualDisplay","textSpans":[]},
          "ATTRIBUTES":{"_type":"AttributesViewHelix","attributeList":#{specifics}},
          "PHOTOS":{"_type":"PhotosViewHelix","epsData":{"uaes":"upload-token"},
            "photosInput":{"photos":[{"url":"https://i.ebayimg.com/one.jpg"},
              {"url":"https://i.ebayimg.com/two.jpg"}]}},
          "nested":{"TITLE":{"_type":"TitleViewHelix",
            "titleField":{"name":"title","value":"Vintage lamp"}}}};
      </script>
    </html>
    """
  end
end
