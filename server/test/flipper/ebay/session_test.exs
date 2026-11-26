defmodule Flipper.Ebay.SessionTest do
  use ExUnit.Case, async: false

  alias Flipper.Ebay.SellerHub.Client
  alias Flipper.Ebay.Session

  setup do
    path = Application.fetch_env!(:flipper, :ebay_cookie_path)
    rejected = path <> ".rejected"
    previous = Application.get_env(:flipper, :ebay_cookie)
    File.rm(path)
    File.rm(rejected)
    Application.put_env(:flipper, :ebay_cookie, nil)
    Session.refresh()

    on_exit(fn ->
      File.rm(path)
      File.rm(rejected)

      if is_binary(previous) and previous != "" do
        Application.put_env(:flipper, :ebay_cookie, previous)
      else
        Application.delete_env(:flipper, :ebay_cookie)
      end

      Session.refresh()
    end)

    %{path: path, rejected: rejected}
  end

  test "rejects a blank cookie", %{path: path} do
    assert {:error, "is blank"} = Session.set("   ")
    assert {:error, "is blank"} = Session.set("cookie:")
    assert is_nil(Session.cookie())
    refute File.exists?(path)
  end

  test "strips one cookie prefix and writes the file", %{path: path} do
    assert :ok = Session.set("Cookie: secret-value")
    assert Session.cookie() == "secret-value"
    assert File.read!(path) == "secret-value"
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  end

  test "reads the file ahead of the env cookie, without copying that to disk", %{path: path} do
    Application.put_env(:flipper, :ebay_cookie, "env-cookie")
    assert Session.cookie() == "env-cookie"
    refute File.exists?(path)

    File.write!(path, "file-cookie\n")
    assert Session.cookie() == "file-cookie"
  end

  test "announces a cookie saved by another server", %{path: path} do
    assert :ok = Session.subscribe()

    File.write!(path, "other-server")

    assert_receive :ebay_session_changed, 3_000
    assert Session.status() == :ok
  end

  test "announces nothing while nothing changes" do
    assert :ok = Session.subscribe()
    assert :ok = Session.refresh()
    refute_received :ebay_session_changed
  end

  test "saves a rejection for every server, without the cookie", %{rejected: rejected} do
    assert :ok = Session.set("secret-value")
    assert :ok = Session.reject("secret-value")

    refute File.read!(rejected) =~ "secret-value"
    assert Bitwise.band(File.stat!(rejected).mode, 0o777) == 0o600
  end

  test "status follows the cookie from missing to saved to rejected" do
    assert Session.status() == :missing

    assert :ok = Session.set("secret-value")
    assert Session.status() == :ok

    assert :ok = Session.reject("secret-value")
    assert Session.status() == :rejected
    assert Session.cookie() == "secret-value"

    assert :ok = Session.set("new-value")
    assert Session.status() == :ok

    assert :ok = Session.reject("new-value")
    assert :ok = Session.set("new-value")
    assert Session.status() == :ok
  end

  test "rejecting an old cookie leaves the current one alone" do
    assert :ok = Session.set("new-value")
    assert :ok = Session.reject("old-value")
    assert Session.status() == :ok
  end

  test "subscribers hear about a new cookie and a rejected one" do
    assert :ok = Session.subscribe()

    assert :ok = Session.set("secret-value")
    assert_received :ebay_session_changed

    assert :ok = Session.reject("old-value")
    refute_received :ebay_session_changed

    assert :ok = Session.reject("secret-value")
    assert_received :ebay_session_changed
  end

  test "a sign-in redirect rejects the cookie" do
    assert :ok = Session.set("secret-value")
    redirect_ebay_to("https://signin.ebay.com/ws/eBayISAPI.dll?SignIn")

    assert {:error, "eBay session is not signed in"} =
             Client.fetch("1", plug: {Req.Test, __MODULE__})

    assert Session.status() == :rejected
  end

  test "a browser check redirect rejects the cookie" do
    assert :ok = Session.set("secret-value")
    redirect_ebay_to("https://www.ebay.com/splashui/challenge?ap=1")

    assert {:error, "eBay asked for a browser check"} =
             Client.fetch("1", plug: {Req.Test, __MODULE__})

    assert Session.status() == :rejected
  end

  test "a browser check page rejects the cookie" do
    assert :ok = Session.set("secret-value")
    answer_with(200, "Pardon Our Interruption")

    assert {:error, "eBay asked for a browser check"} =
             Client.fetch("1", plug: {Req.Test, __MODULE__})

    assert Session.status() == :rejected
  end

  test "a refusal or a rate limit rejects the cookie" do
    for status <- [403, 429] do
      assert :ok = Session.set("secret-value")
      answer_with(status, "")

      assert {:error, "eBay returned " <> _} = Client.fetch("1", plug: {Req.Test, __MODULE__})
      assert Session.status() == :rejected
    end
  end

  test "a server error keeps the cookie" do
    assert :ok = Session.set("secret-value")
    answer_with(500, "")

    assert {:error, "eBay returned 500"} = Client.fetch("1", plug: {Req.Test, __MODULE__})
    assert Session.status() == :ok
  end

  test "listing drafts rejects a signed out cookie" do
    assert :ok = Session.set("secret-value")
    redirect_ebay_to("https://signin.ebay.com/ws/eBayISAPI.dll?SignIn")

    assert {:error, "eBay session is not signed in"} =
             Client.drafts(plug: {Req.Test, __MODULE__})

    assert Session.status() == :rejected
  end

  test "listing drafts asks for 200 and keeps a signed in cookie" do
    assert :ok = Session.set("secret-value")
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(parent, {:requested, conn.request_path, conn.query_string})
      Plug.Conn.send_resp(conn, 200, "<html></html>")
    end)

    assert {:error, "eBay drafts page had no list" <> _} =
             Client.drafts(plug: {Req.Test, __MODULE__})

    assert_received {:requested, "/sh/lst/drafts", "limit=200"}
    assert Session.status() == :ok
  end

  defp answer_with(status, body) do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, status, body))
  end

  defp redirect_ebay_to(location) do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", location)
      |> Plug.Conn.send_resp(307, "")
    end)
  end
end
