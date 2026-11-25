defmodule Flipper.Ebay.Session do
  @moduledoc """
  Keeps the seller's eBay cookie for Seller Hub requests.
  """

  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> stored_cookie() end, Keyword.put_new(opts, :name, __MODULE__))
  end

  def cookie do
    Agent.get(__MODULE__, & &1)
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
        Agent.update(__MODULE__, fn _ -> cookie end)
        :ok
    end
  end

  def load do
    Agent.update(__MODULE__, fn _ -> stored_cookie() end)
    :ok
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
