defmodule CaraWeb.ChatLiveCoverageTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias Cara.AI.Message

  setup %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)
    stub(Cara.AI.ChatMock, :new_context, fn _ -> :initial_context end)
    stub(Cara.AI.ChatMock, :reset_context, fn _ -> :initial_context end)

    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  describe "ChatLive extra coverage" do
    test "toggle_sidebar event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      assert view |> render_hook("toggle_sidebar", %{}) =~ "sidebar"
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.show_sidebar == true
    end

    test "toggle_branches event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("toggle_branches", %{})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.show_branches == true
    end

    test "switch_branch event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      state = :sys.get_state(view.pid)
      msg_id = hd(state.socket.assigns.branched_chat.branches["main"].messages).id

      # First we need another branch to switch to
      view |> render_hook("branch_off", %{"id" => msg_id})
      state = :sys.get_state(view.pid)
      new_branch_id = state.socket.assigns.branched_chat.current_branch_id
      assert new_branch_id != "main"

      # Switch back to main
      view |> render_hook("switch_branch", %{"id" => "main"})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.branched_chat.current_branch_id == "main"
    end

    test "switch_branch with same id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("switch_branch", %{"id" => "main"})
      assert render(view) =~ "Test Student"
    end

    test "branch_off with non-existent id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("branch_off", %{"id" => "non-existent"})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.branched_chat.current_branch_id == "main"
    end

    test "delete_message with id event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      state = :sys.get_state(view.pid)
      msg_id = hd(state.socket.assigns.branched_chat.branches["main"].messages).id

      view |> render_hook("delete_message", %{"id" => msg_id})
      state = :sys.get_state(view.pid)

      assert hd(state.socket.assigns.branched_chat.branches["main"].messages)
             |> Message.deleted?()
    end

    test "delete_message with idx event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("delete_message", %{"idx" => 0})
      state = :sys.get_state(view.pid)

      assert hd(state.socket.assigns.branched_chat.branches["main"].messages)
             |> Message.deleted?()
    end

    test "delete_message with invalid idx", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("delete_message", %{"idx" => 100})
      assert render(view) =~ "Test Student"
    end

    test "cancel event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      send(view.pid, {:llm_status, "main", "Thinking..."})
      view |> render_hook("cancel", %{})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.branched_chat.branches["main"].active_task == nil
    end

    test "handle_info :llm_chunk", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      send(view.pid, {:llm_chunk, "main", "Hello from chunk"})
      assert render(view) =~ "Hello from chunk"
    end

    test "handle_info :llm_status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      send(view.pid, {:llm_status, "main", "Searching Wikipedia..."})
      assert render(view) =~ "Searching Wikipedia..."
    end

    test "handle_info :update_tool_usage_counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      send(view.pid, {:update_tool_usage_counts, %{"calculator" => 1}})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.tool_usage_counts["calculator"] == 1
    end

    test "handle_info :llm_error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      send(view.pid, {:llm_error, "main", "Something went wrong"})
      assert render(view) =~ "Something went wrong"
    end

    test "disabled monitoring", %{conn: conn} do
      Application.put_env(:cara, :enable_teacher_monitoring, false)
      on_exit(fn -> Application.put_env(:cara, :enable_teacher_monitoring, true) end)

      {:ok, view, _html} = live(conn, ~p"/chat")
      view |> render_hook("delete_message", %{"idx" => 0})
      state = :sys.get_state(view.pid)

      assert hd(state.socket.assigns.branched_chat.branches["main"].messages)
             |> Message.deleted?()
    end
  end

  describe "TeacherLive extra coverage" do
    test "handle_info :chat_started new and update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/teacher")

      # New chat
      student1 = %{name: "Student 1", subject: "Math", age: "10"}
      send(view.pid, {:chat_started, %{id: "s1", student: student1}})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.chats["s1"].student.name == "Student 1"

      # Update existing chat
      student1_updated = %{student1 | name: "Student 1 Updated"}
      send(view.pid, {:chat_started, %{id: "s1", student: student1_updated}})
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.chats["s1"].student.name == "Student 1 Updated"
    end

    test "handle_info :chat_left", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/teacher")
      send(view.pid, {:chat_started, %{id: "to-leave", student: %{name: "Leaver", subject: "S", age: "1"}}})
      send(view.pid, {:chat_left, %{id: "to-leave"}})
      state = :sys.get_state(view.pid)
      assert !Map.has_key?(state.socket.assigns.chats, "to-leave")
    end

    test "handle_info :new_message when chat doesn't exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/teacher")
      # Clear if needed
      send(view.pid, {:chat_left, %{id: "test-chat-id"}})
      send(view.pid, {:new_message, %{chat_id: "non-existent", message: %{}}})
      state = :sys.get_state(view.pid)
      assert !Map.has_key?(state.socket.assigns.chats, "non-existent")
    end

    test "handle_info :message_deleted", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/teacher")
      msg = %{id: "m1", sender: :user, content: "hi", deleted: false}
      send(view.pid, {:chat_started, %{id: "c1", student: %{name: "Alice", subject: "S", age: "1"}}})
      send(view.pid, {:new_message, %{chat_id: "c1", message: msg}})

      send(view.pid, {:message_deleted, %{chat_id: "c1", message_id: "m1"}})
      state = :sys.get_state(view.pid)
      assert hd(state.socket.assigns.chats["c1"].messages).deleted == true
    end

    test "handle_info :teacher_joined", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/teacher")
      send(view.pid, {:teacher_joined, nil})
      assert render(view) =~ "Teacher Dashboard"
    end
  end
end
