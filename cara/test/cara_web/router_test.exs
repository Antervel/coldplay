defmodule CaraWeb.RouterTest do
  use CaraWeb.ConnCase
  import Mox

  setup :verify_on_exit!

  test "GET /renders home page", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Cara"
  end

  test "GET /settings renders settings page", %{conn: conn} do
    conn = get(conn, "/settings")
    assert html_response(conn, 200) =~ "Settings"
  end

  test "GET /student renders student page", %{conn: conn} do
    conn = get(conn, "/student")
    assert html_response(conn, 200) =~ "Tell me about yourself!"
  end

  test "GET /teacher renders teacher page", %{conn: conn} do
    conn = get(conn, "/teacher")
    assert html_response(conn, 200) =~ "Teacher Dashboard"
  end

  test "GET /sleeping renders sleeping page", %{conn: conn} do
    conn = get(conn, "/sleeping")
    assert html_response(conn, 200) =~ "The AI is Sleeping"
  end

  test "GET /chat redirects to /student if no session", %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)
    conn = get(conn, "/chat")
    assert redirected_to(conn) == "/student"
  end

  test "GET /chat renders chat page with student session", %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> :test_context end)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-id"}

    conn =
      conn
      |> init_test_session(%{student_info: student_info})
      |> get("/chat")

    assert html_response(conn, 200) =~ "Cara"
  end
end
