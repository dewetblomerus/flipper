defmodule Flipper.Photos.Editor do
  @moduledoc """
  Straightens a photo, crops it to its subject, and reports the angle and box.
  """

  @callback crop(input :: String.t(), output :: String.t(), title :: String.t() | nil) ::
              {:ok, map()} | {:error, term()}
end
