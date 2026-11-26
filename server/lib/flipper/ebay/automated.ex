defmodule Flipper.Ebay.Automated do
  @moduledoc "Serializes and paces unattended eBay work on this server."

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: __MODULE__)

  def run(function) do
    :global.trans(
      {__MODULE__, self()},
      fn ->
        if Keyword.get(Application.get_env(:flipper, __MODULE__, []), :pace, true), do: pace()
        function.()
      end,
      [node()]
    )
  end

  defp pace do
    case Registry.meta(__MODULE__, :next_start) do
      {:ok, deadline} -> Process.sleep(max(0, deadline - System.monotonic_time(:millisecond)))
      :error -> :ok
    end

    delay = 4_999 + :rand.uniform(10_001)
    Registry.put_meta(__MODULE__, :next_start, System.monotonic_time(:millisecond) + delay)
  end
end
