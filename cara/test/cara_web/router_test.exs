defmodule CaraWeb.RouterTest do
  use CaraWeb.ConnCase
  import Mox

  setup :verify_on_exit!

  test "GET / renders home page", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production."
  end

  test "GET /chat renders chat page", %{conn: conn} do
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> :test_context end)
    conn = get(conn, "/chat")
    assert html_response(conn, 200) =~ "Chat"
  end
end
