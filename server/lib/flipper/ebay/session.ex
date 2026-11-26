defmodule Flipper.Ebay.Session do
  @moduledoc """
  Keeps the seller's eBay cookie for Seller Hub requests, and why eBay rejected it.

  Both are files, shared by every server on the machine. Each server watches them and
  tells its subscribers about a change.
  """

  use GenServer

  @topic "ebay_session"
  @poll_ms 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, Keyword.put_new(opts, :name, __MODULE__))
  end

  def cookie do
    read(path()) || present(Application.get_env(:flipper, :ebay_cookie))
  end

  def status, do: status(cookie())

  @doc """
  Returns `%{status: status, error: reason}` while eBay rejects the cookie, or nil. A
  rejection holding only the cookie's digest has a nil status.
  """
  def rejection(cookie \\ cookie())

  def rejection(nil), do: nil

  def rejection(cookie), do: parse_rejection(read(rejected_path()), digest(cookie))

  def subscribe do
    Phoenix.PubSub.subscribe(Flipper.PubSub, @topic)
  end

  def set(value) when is_binary(value) do
    case normalize(value) do
      "" ->
        {:error, "is blank"}

      cookie ->
        write(path(), cookie)
        File.rm(rejected_path())
        refresh()
    end
  end

  @doc """
  Saves eBay's response to the current cookie. A rejection of any other cookie is ignored.
  """
  def reject(cookie, status, error) when is_binary(cookie) do
    if cookie == cookie() do
      rejection = %{cookie: digest(cookie), status: status, error: error}
      write(rejected_path(), Jason.encode!(rejection))
      refresh()
    else
      :ok
    end
  end

  @doc """
  Tells subscribers about a change now, ahead of the next poll.
  """
  def refresh, do: GenServer.call(__MODULE__, :refresh)

  @impl true
  def init(nil) do
    schedule_poll()
    {:ok, snapshot()}
  end

  @impl true
  def handle_call(:refresh, _from, seen), do: {:reply, :ok, announce(seen)}

  @impl true
  def handle_info(:poll, seen) do
    schedule_poll()
    {:noreply, announce(seen)}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_ms)

  defp announce(seen) do
    case snapshot() do
      ^seen ->
        seen

      changed ->
        Phoenix.PubSub.broadcast(Flipper.PubSub, @topic, :ebay_session_changed)
        changed
    end
  end

  # A digest keeps the cookie out of the process state and its crash reports.
  defp snapshot do
    cookie = cookie()
    {status(cookie), cookie && digest(cookie)}
  end

  defp status(nil), do: :missing

  defp status(cookie), do: if(rejection(cookie), do: :rejected, else: :ok)

  defp parse_rejection(nil, _digest), do: nil

  # Servers on this machine can run code that saves only the digest.
  defp parse_rejection(digest, digest), do: %{status: nil, error: "eBay refused the cookie"}

  defp parse_rejection(value, digest) do
    case Jason.decode(value) do
      {:ok, %{"cookie" => ^digest, "status" => status, "error" => error}} ->
        %{status: status, error: error}

      _ ->
        nil
    end
  end

  defp digest(cookie), do: :sha256 |> :crypto.hash(cookie) |> Base.encode16()

  defp read(path) do
    case File.read(path) do
      {:ok, value} -> present(value)
      {:error, _reason} -> nil
    end
  end

  # Renaming a private temporary file keeps other servers from reading half a value.
  defp write(path, value) do
    temporary = "#{path}.#{System.pid()}-#{System.unique_integer([:positive])}"
    File.mkdir_p!(Path.dirname(path))
    File.touch!(temporary)
    File.chmod!(temporary, 0o600)
    File.write!(temporary, value)
    File.rename!(temporary, path)
  end

  defp normalize(value) do
    value
    |> String.trim()
    |> String.replace(~r/\Acookie:/i, "")
    |> String.trim()
  end

  defp present(cookie) when is_binary(cookie) do
    case String.trim(cookie) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_cookie), do: nil

  defp path do
    Application.fetch_env!(:flipper, :ebay_cookie_path)
  end

  defp rejected_path, do: path() <> ".rejected"
end
