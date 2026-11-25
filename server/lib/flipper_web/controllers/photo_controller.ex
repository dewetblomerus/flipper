defmodule FlipperWeb.PhotoController do
  use FlipperWeb, :controller

  alias Flipper.Drafts

  def show(conn, %{"id" => id}) do
    send_photo(conn, id, :original)
  end

  def edited(conn, %{"id" => id}) do
    send_photo(conn, id, :edited)
  end

  defp send_photo(conn, id, version) do
    case Drafts.photo_file(Drafts.get_photo!(id), version) do
      {:ok, path, type} ->
        conn
        |> put_resp_content_type(type)
        |> send_file(200, path)

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end
end
