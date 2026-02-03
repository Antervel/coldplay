defmodule CaraWeb.StudentControllerTest do
  use CaraWeb.ConnCase

  test "index deletes student_info from session and renders index", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{"student_info" => %{name: "Test", age: "10", subject: "Math"}})
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

    assert get_session(conn, :student_info) == %{
             name: "New Student",
             age: "12",
             subject: "Science"
           }

    assert redirected_to(conn) == "/chat"
  end
end
