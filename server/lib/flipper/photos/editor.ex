defmodule Flipper.Photos.Editor do
  @moduledoc """
  Crops a photo to its subject, brightens it, and reports that box in original pixels.
  """

  @callback crop(input :: String.t(), output :: String.t(), title :: String.t() | nil) ::
              {:ok, map()} | {:error, term()}
end
