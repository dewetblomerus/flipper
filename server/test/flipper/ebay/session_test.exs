defmodule Flipper.Ebay.SessionTest do
  use ExUnit.Case, async: false

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

    %{path: path}
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

  test "loads the file without copying the env cookie to disk", %{path: path} do
    Application.put_env(:flipper, :ebay_cookie, "env-cookie")
    assert :ok = Session.load()
    assert Session.cookie() == "env-cookie"
    refute File.exists?(path)

    File.write!(path, "file-cookie")
    assert :ok = Session.load()
    assert Session.cookie() == "file-cookie"
    assert File.read!(path) == "file-cookie"
  end

  test "load reads the saved file back into memory", %{path: path} do
    assert :ok = Session.set("secret-value")
    Agent.update(Session, fn _ -> nil end)
    assert is_nil(Session.cookie())

    assert :ok = Session.load()
    assert Session.cookie() == "secret-value"
    assert File.read!(path) == "secret-value"
  end
end
