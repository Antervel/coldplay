defmodule CaraWeb.PageController do
  use CaraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def sleeping(conn, _params) do
    render(conn, :sleeping)
  end

  def settings(conn, _params) do
    render(conn, :settings)
  end
end
