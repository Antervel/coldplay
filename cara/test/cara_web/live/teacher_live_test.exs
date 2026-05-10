defmodule CaraWeb.TeacherLiveTest do
  use CaraWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Phoenix.PubSub

  test "teacher dashboard shows active students and messages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/teacher")

    chat_id = "test-chat-id"
    student = %{name: "Alice", subject: "Math", age: "10"}

    # Simulate a chat starting
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:chat_started, %{id: chat_id, student: student}})

    assert render(view) =~ "Alice"
    assert render(view) =~ "Math"

    # Simulate a new message
    message = %{sender: :user, content: "Hello Cara!", id: "msg-1", deleted: false}
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:new_message, %{chat_id: chat_id, message: message}})

    assert render(view) =~ "Hello Cara!"

    # Simulate a deleted message
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:message_deleted, %{chat_id: chat_id, message_id: "msg-1"}})

    assert render(view) =~ "Deleted by student"

    # Simulate student leaving
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:chat_left, %{id: chat_id}})

    refute render(view) =~ "Alice"
  end

  test "teacher dashboard updates border color based on safety score", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/teacher")

    chat_id = "color-chat-id"
    student = %{name: "Peter", subject: "Science", age: "14"}

    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:chat_started, %{id: chat_id, student: student}})

    # Default/Safe (0.0)
    assert render(view) =~ "border-green-500"

    # Safe question (0.1)
    message1 = %{sender: :user, content: "What is integrals?", id: "msg-1", metadata: %{safety_score: 0.1}}
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:new_message, %{chat_id: chat_id, message: message1}})
    assert render(view) =~ "border-green-500"

    # Inconvenient question (0.5)
    message2 = %{sender: :user, content: "How are babies born?", id: "msg-2", metadata: %{safety_score: 0.5}}
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:new_message, %{chat_id: chat_id, message: message2}})
    assert render(view) =~ "border-yellow-400"

    # Escalation (0.9)
    message3 = %{sender: :user, content: "Bad stuff", id: "msg-3", metadata: %{safety_score: 0.9}}
    PubSub.broadcast(Cara.PubSub, "teacher:monitor", {:new_message, %{chat_id: chat_id, message: message3}})
    assert render(view) =~ "border-red-500"
  end

  test "teacher dashboard requests state on mount", %{conn: conn} do
    # Subscribe to monitor teacher joined events
    PubSub.subscribe(Cara.PubSub, "teacher:monitor")

    {:ok, _view, _html} = live(conn, "/teacher")

    assert_receive {:teacher_joined, nil}
  end

  test "teacher dashboard handles state sync", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/teacher")

    chat_id = "sync-chat-id"
    student = %{name: "Bob", subject: "History", age: "12"}

    messages = [
      %{sender: :user, content: "Hi", id: "m1", deleted: false},
      %{sender: :assistant, content: "Hello Bob!", id: "m2", deleted: true}
    ]

    PubSub.broadcast(
      Cara.PubSub,
      "teacher:monitor",
      {:chat_state, %{id: chat_id, student: student, messages: messages}}
    )

    html = render(view)
    assert html =~ "Bob"
    assert html =~ "History"
    assert html =~ "Hi"
    assert html =~ "Deleted by student"
    assert html =~ "Hello Bob!"
  end

  test "teacher dashboard shows disabled message when config is false", %{conn: conn} do
    Application.put_env(:cara, :enable_teacher_monitoring, false)
    on_exit(fn -> Application.put_env(:cara, :enable_teacher_monitoring, true) end)

    {:ok, view, _html} = live(conn, "/teacher")
    assert render(view) =~ "Monitoring is disabled"
  end
end
