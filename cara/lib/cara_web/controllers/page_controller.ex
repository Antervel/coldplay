defmodule CaraWeb.PageController do
  use CaraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
