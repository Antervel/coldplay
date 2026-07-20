defmodule CaraWeb.StudentController do
  use CaraWeb, :controller

  alias Cara.Audit

  def index(conn, _params) do
    conn
    |> delete_session(:student_info)
    |> render(:index)
  end

  def create(conn, %{"student" => student_params}) do
    chat_id = Ecto.UUID.generate()

    student_info = %{
      chat_id: chat_id,
      name: student_params["name"],
      age: student_params["age"],
      subject: student_params["subject"]
    }

    # Persist session for audit log viewer
    Audit.create_session(%{
      chat_id: chat_id,
      student_name: student_params["name"],
      student_age: elem(Integer.parse(student_params["age"]), 0),
      student_subject: student_params["subject"]
    })

    conn
    |> put_session(:student_info, student_info)
    |> redirect(to: ~p"/chat")
  end
end
