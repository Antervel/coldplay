defmodule CaraWeb.PageController do
  use CaraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def sleeping(conn, _params) do
    render(conn, :sleeping)
  end
end
