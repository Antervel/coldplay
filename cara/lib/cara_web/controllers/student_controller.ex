defmodule CaraWeb.StudentController do
  use CaraWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end

  def create(conn, %{"student" => student_params}) do
    student_info = %{
      name: student_params["name"],
      age: student_params["age"],
      subject: student_params["subject"]
    }

    conn
    |> put_session(:student_info, student_info)
    |> redirect(to: ~p"/chat")
  end
end
