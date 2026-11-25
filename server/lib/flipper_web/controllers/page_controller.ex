defmodule FlipperWeb.PageController do
  use FlipperWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
