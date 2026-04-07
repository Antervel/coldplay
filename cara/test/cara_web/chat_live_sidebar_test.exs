defmodule CaraWeb.ChatLiveSidebarTest do
  use CaraWeb.ConnCase
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  defp setup_chat(conn) do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> :test_context end)

    student_info = %{
      name: "Test Student",
      age: "10",
      subject: "Science",
      chat_id: "test-chat-id"
    }

    conn =
      conn
      |> init_test_session(%{student_info: student_info})

    {:ok, view, _html} = live(conn, "/chat")
    %{view: view, student_info: student_info}
  end

  test "toggling the sidebar menu", %{conn: conn} do
    %{view: view} = setup_chat(conn)

    # Initially sidebar is hidden
    refute render(view) =~ "Student Info"

    # Click hamburger button
    view |> element("button[title='Menu']") |> render_click()

    # Sidebar should be visible
    assert render(view) =~ "Student Info"
    assert render(view) =~ "Test Student"

    # Click away or toggle again
    view |> element("button[title='Menu']") |> render_click()
    # Or use click_away if we can target it, but toggle_sidebar is also on the overlay
    # For simplicity, toggle again
    refute render(view) =~ "Student Info"
  end

  test "sidebar navigation links", %{conn: conn} do
    %{view: view} = setup_chat(conn)

    # Open sidebar
    view |> element("button[title='Menu']") |> render_click()

    # Settings link
    assert view |> element("a[href='/settings']", "Settings") |> render() =~ "Settings"

    # Leave Chat link
    assert view |> element("a[href='/student']", "Leave Chat") |> render() =~ "Leave Chat"
  end
end
