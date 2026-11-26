defmodule Flipper.Ebay.SellerHubRemovalTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.Client

  @tokens ~S|<div data-srt="{&quot;/lstng/api/listing_draft/:draftId(\\d+)/skip_validation&quot;:&quot;photo-token&quot;,&quot;/lstng/api/listing_draft/:draftId(\\d+)&quot;:&quot;draft-token&quot;}"></div>|

  test "each route has its own token" do
    assert {:ok, "draft-token"} = Client.draft_token(@tokens)
    assert {:ok, "photo-token"} = Client.save_token(@tokens)
    assert {:error, _} = Client.draft_token("<html></html>")
  end

  test "read_draft returns every data module without upload tokens" do
    server = draft_server([page(color: "Black")])

    assert {:ok, modules} = Client.read_draft("123", cookie: "session", plug: server)

    assert Map.keys(modules) == ["ATTRIBUTES", "PHOTOS", "TITLE"]
    assert modules["TITLE"]["_type"] == "TitleViewHelix"

    assert modules["PHOTOS"] == %{
             "_type" => "PhotosViewHelix",
             "photosInput" => %{"photos" => [%{"url" => "https://i.ebayimg.com/one.jpg"}]}
           }
  end

  test "a page without a draft is an error" do
    server = draft_server(["<html></html>"])

    assert {:error, "eBay listing page had no draft"} =
             Client.read_draft("123", cookie: "session", plug: server)
  end

  test "remove_fields saves on the main route and reads the draft back" do
    server = draft_server([page(color: "Black"), page(color: nil)])

    assert :ok =
             Client.remove_fields("123", ["attributes.Color"], cookie: "session", plug: server)

    assert_received {:put, "/lstng/api/listing_draft/123", ["draft-token"], body}
    assert body["attributes"] == %{"Color" => []}
    assert body["removedFields"] == []
    assert is_binary(body["requestId"])
    assert is_integer(body["requestMeta"]["lastDeltaTimestamp"])
    refute Map.has_key?(body, "pictures")
  end

  test "remove_fields fails when eBay keeps a field" do
    server = draft_server([page(color: "Black")])

    assert {:error, "eBay draft kept Color"} =
             Client.remove_fields("123", ["attributes.Color"], cookie: "session", plug: server)
  end

  test "remove_fields fails when a kept field is no longer optional" do
    for changed <- [[groups: ["REQUIRED"]], [read_only: true]] do
      server = draft_server([page(color: "Black"), page([color: "Black"] ++ changed)])

      assert {:error, "eBay draft kept Color"} =
               Client.remove_fields("123", ["attributes.Color"], cookie: "session", plug: server)
    end
  end

  test "remove_fields with nothing to remove makes no request" do
    assert :ok = Client.remove_fields("123", [], cookie: nil)
  end

  # Serves the pages in order, repeating the last, and reports each save.
  defp draft_server(pages) do
    parent = self()
    agent = start_supervised!({Agent, fn -> pages end}, id: make_ref())
    name = {:ebay, self(), System.unique_integer([:positive])}

    Req.Test.stub(name, fn
      %{method: "GET"} = conn ->
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
            "photosInput":{"photos":[{"url":"https://i.ebayimg.com/one.jpg"}]}},
          "nested":{"TITLE":{"_type":"TitleViewHelix"}}};
      </script>
    </html>
    """
  end
end
