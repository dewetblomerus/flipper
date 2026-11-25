defmodule Flipper.Ebay.Session do
  @moduledoc """
  Keeps the seller's eBay cookie for Seller Hub requests, and whether eBay rejected it.
  """

  use Agent

  @topic "ebay_session"

  def start_link(opts \\ []) do
    Agent.start_link(fn -> stored_state() end, Keyword.put_new(opts, :name, __MODULE__))
  end

  def cookie do
    Agent.get(__MODULE__, & &1.cookie)
  end

  def status do
    case Agent.get(__MODULE__, & &1) do
      %{cookie: nil} -> :missing
      %{rejected: true} -> :rejected
      %{} -> :ok
    end
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Flipper.PubSub, @topic)
  end

  def set(value) when is_binary(value) do
    case normalize(value) do
      "" ->
        {:error, "is blank"}

      cookie ->
        path = path()
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, cookie)
        File.chmod!(path, 0o600)
        Agent.update(__MODULE__, fn _ -> new_state(cookie) end)
        broadcast_changed()
    end
  end

  def reject(cookie) when is_binary(cookie) do
    current? =
      Agent.get_and_update(__MODULE__, fn
        %{cookie: ^cookie} = state -> {true, %{state | rejected: true}}
        state -> {false, state}
      end)

    if current?, do: broadcast_changed(), else: :ok
  end

  def load do
    Agent.update(__MODULE__, fn _ -> stored_state() end)
  end

  defp new_state(cookie), do: %{cookie: cookie, rejected: false}

  defp stored_state, do: new_state(stored_cookie())

  defp broadcast_changed do
    Phoenix.PubSub.broadcast(Flipper.PubSub, @topic, :ebay_session_changed)
  end

  defp stored_cookie do
    case read_file() do
      cookie when is_binary(cookie) and cookie != "" -> cookie
      _ -> present(Application.get_env(:flipper, :ebay_cookie))
    end
  end

  defp read_file do
    case File.read(path()) do
      {:ok, value} -> String.trim(value)
      {:error, _reason} -> nil
    end
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
end
