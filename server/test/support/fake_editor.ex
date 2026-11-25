defmodule Flipper.Photos.FakeEditor do
  @moduledoc """
  Writes a stand-in edit, a fixed subject box, and a fixed angle.
  """

  @behaviour Flipper.Photos.Editor

  @impl true
  def crop(_input, output, _title) do
    File.write!(output, "edited")
    send(self(), {:photo_cropped, output})
    {:ok, %{left: 1, top: 2, width: 3, height: 4, angle: -5.5, content_type: "image/png"}}
  end
end
