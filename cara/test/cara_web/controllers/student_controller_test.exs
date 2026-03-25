defmodule CaraWeb.StudentControllerTest do
  use CaraWeb.ConnCase

  test "index deletes student_info from session and renders index", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "student_info" => %{name: "Test", age: "10", subject: "Math", chat_id: "test-id"}
      })
      |> fetch_session()
      |> get("/student")

    assert get_session(conn, :student_info) == nil
    assert html_response(conn, 200) =~ "What's your name?"
  end

  test "create puts student_info into session and redirects to /chat", %{conn: conn} do
    params = %{
      "student" => %{
        "name" => "New Student",
        "age" => "12",
        "subject" => "Science"
      }
    }

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> fetch_session()
      |> post("/student", params)

    student_info = get_session(conn, :student_info)
    assert student_info.name == "New Student"
    assert student_info.age == "12"
    assert student_info.subject == "Science"
    assert Map.has_key?(student_info, :chat_id)

    assert redirected_to(conn) == "/chat"
  end
end
