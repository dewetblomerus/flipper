defmodule Flipper.Ebay.Session do
  @moduledoc """
  Keeps the seller's eBay cookie for Seller Hub requests, and whether eBay rejected it.

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

  def reject(cookie) when is_binary(cookie) do
    if cookie == cookie() do
      write(rejected_path(), digest(cookie))
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

  defp status(cookie) do
    if read(rejected_path()) == digest(cookie), do: :rejected, else: :ok
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
