defmodule Flipper.Photos.FakeEditor do
  @moduledoc """
  Writes a stand-in edit and a fixed subject box.
  """

  @behaviour Flipper.Photos.Editor

  @impl true
  def crop(_input, output, _title) do
    File.write!(output, "edited")
    send(self(), {:photo_cropped, output})
    {:ok, %{left: 1, top: 2, width: 3, height: 4, content_type: "image/png"}}
  end
end
