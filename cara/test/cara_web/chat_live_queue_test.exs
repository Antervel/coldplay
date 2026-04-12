defmodule CaraWeb.ChatLiveQueueTest do
  use CaraWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  alias BranchedLLM.BranchedChat
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    stub(Cara.AI.ChatMock, :reset_context, fn ctx ->
      system_msgs = Enum.filter(ctx.messages, fn msg -> msg.role == :system end)
      ReqLLM.Context.new(system_msgs)
    end)

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

  test "messages are queued when AI is busy in the same branch", %{conn: conn} do
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

    # Send first message in main
    view |> form("form", chat: %{message: "First"}) |> render_submit()
    assert_receive {:llm_call_started, "First", stream_pid1}, 500

    # Send second message in main immediately
    view |> form("form", chat: %{message: "Second"}) |> render_submit()

    # Verify second message is in the UI as a user message
    assert render(view) =~ "Second"

    # Verify second message has NOT triggered an LLM call yet
    refute_received {:llm_call_started, "Second", _}

    # Verify state shows it's queued in main branch
    state = :sys.get_state(view.pid)
    branched_chat = state.socket.assigns.branched_chat
    main_branch = branched_chat.branches["main"]
    assert main_branch.pending_messages == ["Second"]
    assert main_branch.active_task != nil

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

    # Verify queue is empty and no active task in main branch
    state = :sys.get_state(view.pid)
    main_branch = state.socket.assigns.branched_chat.branches["main"]
    assert main_branch.pending_messages == []
    assert main_branch.active_task == nil
  end

  test "messages are NOT queued across different branches", %{conn: conn} do
    test_pid = self()
    initial_ctx = real_context()
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> initial_ctx end)

    # Mock controlled stream
    stub(Cara.AI.ChatMock, :send_message_stream, fn message, _context, _opts ->
      stream_pid = self()
      send(test_pid, {:llm_call_started, message, stream_pid})

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

    # 1. Send message in Main
    view |> form("form", chat: %{message: "MainMsg"}) |> render_submit()
    assert_receive {:llm_call_started, "MainMsg", main_stream_pid}, 500

    # 2. Branch off from the welcome message (idx 0)
    state = :sys.get_state(view.pid)
    welcome_id = hd(BranchedChat.get_current_messages(state.socket.assigns.branched_chat)).id
    view |> render_hook("branch_off", %{id: welcome_id})

    state = :sys.get_state(view.pid)
    new_branch_id = state.socket.assigns.branched_chat.current_branch_id
    assert new_branch_id != "main"

    # 3. Send message in new branch - should start IMMEDIATELY, not queue
    view |> form("form", chat: %{message: "BranchMsg"}) |> render_submit()

    # Verify BranchMsg started immediately
    assert_receive {:llm_call_started, "BranchMsg", branch_stream_pid}, 500

    # Both should be active
    state = :sys.get_state(view.pid)
    branched_chat = state.socket.assigns.branched_chat
    assert branched_chat.branches["main"].active_task != nil
    assert branched_chat.branches[new_branch_id].active_task != nil

    # Finish both
    send(main_stream_pid, {:continue_stream, "MainMsg", [ReqLLM.StreamChunk.text("MainResp")]})
    send(branch_stream_pid, {:continue_stream, "BranchMsg", [ReqLLM.StreamChunk.text("BranchResp")]})

    :timer.sleep(200)

    # Verify current branch shows its response
    assert render(view) =~ "BranchResp"

    # Switch back to main
    view |> render_click("switch_branch", %{id: "main"})
    assert render(view) =~ "MainResp"
  end

  test "cancellation stops the active task for the specific branch", %{conn: conn} do
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

    # Start message in main
    view |> form("form", chat: %{message: "Main Task"}) |> render_submit()
    assert_receive {:llm_call_started, "Main Task", _}

    state_before = :sys.get_state(view.pid)
    active_pid = state_before.socket.assigns.branched_chat.branches["main"].active_task
    assert Process.alive?(active_pid)

    # Cancel
    view |> element("button[phx-click='cancel']") |> render_click()

    # Verify task is killed
    refute Process.alive?(active_pid)

    # Verify branch state is reset
    state_after = :sys.get_state(view.pid)
    main_branch = state_after.socket.assigns.branched_chat.branches["main"]
    assert main_branch.active_task == nil
    assert main_branch.pending_messages == []
    assert main_branch.tool_status == nil

    # Verify UI reflects cancellation
    assert render(view) =~ "*Cancelled*"
  end
end
