defmodule Flipper.Photos.Editor do
  @moduledoc """
  Crops a photo to its subject and reports that box in original pixels.
  """

  @callback crop(input :: String.t(), output :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
