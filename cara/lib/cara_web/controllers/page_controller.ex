defmodule CaraWeb.PageController do
  use CaraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def sleeping(conn, _params) do
    render(conn, :sleeping)
  end

  def settings(conn, _params) do
    current_model = Application.get_env(:cara, :ai_model, "openai:cara-cpu")
    render(conn, :settings, current_model: current_model)
  end

  def update_model(conn, %{"model" => model}) do
    Application.put_env(:cara, :ai_model, model)

    conn
    |> put_flash(:info, "Model updated to #{model}")
    |> redirect(to: ~p"/settings")
  end
end
