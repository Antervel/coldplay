defmodule CaraWeb.ChatLiveNoSessionTest do
  use CaraWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  test "redirects to /student if session is missing", %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    # Ensure session is empty
    conn = Plug.Test.init_test_session(conn, %{})
    assert {:error, {:redirect, %{to: "/student"}}} = live(conn, "/chat")
  end
end
