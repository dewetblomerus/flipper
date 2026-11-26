defmodule Flipper.Photos.GroundingDino do
  @moduledoc """
  Finds the product box with local Grounding DINO, then crops and brightens the original.
  """

  @behaviour Flipper.Photos.Editor

  @impl true
  def crop(input, output, title)
      when is_binary(input) and is_binary(output) and (is_binary(title) or is_nil(title)) do
    python = Application.fetch_env!(:flipper, :photo_edit_python)
    script = Application.app_dir(:flipper, "priv/photo_edit.py")

    case System.cmd(python, [script, input, output, title || ""], stderr_to_stdout: true) do
      {out, 0} -> decode_box(out)
      {out, status} -> {:error, "photo edit exited #{status}: #{String.trim(out)}"}
    end
  end

  defp decode_box(out) do
    json = out |> String.split("\n", trim: true) |> List.last()

    case Jason.decode(json || "") do
      {:ok, %{"left" => left, "top" => top, "width" => width, "height" => height}}
      when is_integer(left) and is_integer(top) and is_integer(width) and is_integer(height) ->
        {:ok, %{left: left, top: top, width: width, height: height, content_type: "image/png"}}

      _ ->
        {:error, "photo edit returned #{String.trim(out)}"}
    end
  end
end
