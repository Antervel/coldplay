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
    stub(Cara.AI.ChatMock, :health_check, fn _opts -> :ok end)
    conn = get(conn, "/chat")
    assert redirected_to(conn) == "/student"
  end

  test "GET /chat renders chat page with student session", %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn _opts -> :ok end)
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> :test_context end)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-id"}

    conn =
      conn
      |> init_test_session(%{student_info: student_info})
      |> get("/chat")

    assert html_response(conn, 200) =~ "Cara"
  end

  test "POST /settings/model updates model and redirects", %{conn: conn} do
    original = Application.get_env(:cara, :ai_model)

    conn = post(conn, "/settings/model", %{"model" => "llama3"})
    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Model updated"

    Application.put_env(:cara, :ai_model, original)
  end

  test "POST /settings/model with nvidia model", %{conn: conn} do
    original = Application.get_env(:cara, :ai_model)

    conn = post(conn, "/settings/model", %{"model" => "openai:openai/gpt-oss-20b"})
    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Model updated"

    Application.put_env(:cara, :ai_model, original)
  end

  test "POST /settings/model with referer header redirects to referer", %{conn: conn} do
    original = Application.get_env(:cara, :ai_model)

    conn =
      conn
      |> put_req_header("referer", "http://localhost/settings")
      |> post("/settings/model", %{"model" => "llama3"})

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Model updated"

    Application.put_env(:cara, :ai_model, original)
  end

  test "POST /settings/model with non-allowed referer redirects to /settings", %{conn: conn} do
    original = Application.get_env(:cara, :ai_model)

    conn =
      conn
      |> put_req_header("referer", "http://localhost/chat")
      |> post("/settings/model", %{"model" => "llama3"})

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Model updated"

    Application.put_env(:cara, :ai_model, original)
  end
end
