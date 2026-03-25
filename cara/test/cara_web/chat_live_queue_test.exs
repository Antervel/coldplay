defmodule CaraWeb.ChatLiveQueueTest do
  use CaraWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  setup :verify_on_exit!

  defp real_context do
    ReqLLM.Context.new([ReqLLM.Context.system("System prompt")])
  end

  test "messages are queued when AI is busy", %{conn: conn} do
    test_pid = self()
    initial_ctx = real_context()
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> initial_ctx end)

    # Use a controlled stream that stays open until we say so
    stub(Cara.AI.ChatMock, :send_message_stream, fn message, _context, _opts ->
      stream_pid = self()
      send(test_pid, {:llm_call_started, message, stream_pid})

      # A stream that waits for a message to continue
      stream =
        Stream.resource(
          fn -> :waiting end,
          fn
            :waiting ->
              receive do
                {:continue_stream, ^message, chunks} -> {chunks, :done}
              after
                1000 -> {:halt, :timeout}
              end

            :done ->
              {:halt, :done}
          end,
          fn _ -> :ok end
        )

      stream_response = %StreamResponse{
        context: %ReqLLM.Context{messages: []},
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: stream,
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _content -> :updated_context end, []}
    end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Send first message
    view |> form("form", chat: %{message: "First"}) |> render_submit()
    assert_receive {:llm_call_started, "First", stream_pid1}, 500

    # Send second message immediately
    view |> form("form", chat: %{message: "Second"}) |> render_submit()

    # Verify second message is in the UI as a user message
    assert render(view) =~ "Second"

    # Verify second message has NOT triggered an LLM call yet
    refute_received {:llm_call_started, "Second", _}

    # Verify state shows it's queued
    state = :sys.get_state(view.pid)
    assert state.socket.assigns.pending_messages == ["Second"]
    assert state.socket.assigns.active_task != nil

    # Finish first stream
    send(stream_pid1, {:continue_stream, "First", [ReqLLM.StreamChunk.text("Response 1")]})

    # Now second message should be started
    assert_receive {:llm_call_started, "Second", stream_pid2}, 1000

    # Finish second stream
    send(stream_pid2, {:continue_stream, "Second", [ReqLLM.StreamChunk.text("Response 2")]})

    :timer.sleep(200)

    # Verify both responses are in UI
    html = render(view)
    assert html =~ "Response 1"
    assert html =~ "Response 2"

    # Verify queue is empty and no active task
    state = :sys.get_state(view.pid)
    assert state.socket.assigns.pending_messages == []
    assert state.socket.assigns.active_task == nil
  end

  test "cancellation stops the active task and clears the queue", %{conn: conn} do
    test_pid = self()
    initial_ctx = real_context()
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> initial_ctx end)

    stub(Cara.AI.ChatMock, :send_message_stream, fn message, _context, _opts ->
      send(test_pid, {:llm_call_started, message, self()})

      # Infinite stream
      stream =
        Stream.repeatedly(fn ->
          Process.sleep(100)
          ReqLLM.StreamChunk.text(".")
        end)

      stream_response = %StreamResponse{
        context: %ReqLLM.Context{messages: []},
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: stream,
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _content -> :updated_context end, []}
    end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Start first message
    view |> form("form", chat: %{message: "Long task"}) |> render_submit()
    assert_receive {:llm_call_started, "Long task", _}

    # Queue second message
    view |> form("form", chat: %{message: "Queued"}) |> render_submit()

    state_before = :sys.get_state(view.pid)
    active_pid = state_before.socket.assigns.active_task
    assert Process.alive?(active_pid)

    # Cancel
    view |> element("button[phx-click='cancel']") |> render_click()

    # Verify task is killed
    refute Process.alive?(active_pid)

    # Verify state is reset
    state_after = :sys.get_state(view.pid)
    assert state_after.socket.assigns.active_task == nil
    assert state_after.socket.assigns.pending_messages == []
    assert state_after.socket.assigns.tool_status == nil

    # Verify UI reflects cancellation
    assert render(view) =~ "*Cancelled*"

    # Verify the queued message was NOT started
    refute_received {:llm_call_started, "Queued", _}
  end
end
