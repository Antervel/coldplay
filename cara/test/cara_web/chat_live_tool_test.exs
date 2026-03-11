defmodule CaraWeb.ChatLiveToolTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    # Initialize test session
    conn = Plug.Test.init_test_session(conn, %{})
    # Fetch the session
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  # Define mock
  setup :verify_on_exit!

  test "handles tool calls and preserves user message in context", %{conn: conn} do
    # Initial context with system prompt
    initial_context = Context.new([Context.system("You are helpful")])
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> initial_context end)

    test_pid = self()

    # Define the sequence of LLM calls
    # 1. First call: user message "Who is X?", returns a tool call
    # 2. Second call: empty message, returns the final answer

    expect(Cara.AI.ChatMock, :send_message_stream, fn "Who is X?", context, _opts ->
      # Simulate adding user message (normally done by Chat.send_message_stream)
      updated_context = Context.append(context, Context.user("Who is X?"))

      tool_calls = [
        ReqLLM.ToolCall.new("call_1", "wikipedia_search", Jason.encode!(%{"query" => "X"}))
      ]

      stream_response = %StreamResponse{
        context: updated_context,
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [%ReqLLM.StreamChunk{type: :content, text: ""}],
        metadata_task: Task.async(fn -> %{} end)
      }

      builder = fn _text -> updated_context end

      {:ok, stream_response, builder, tool_calls}
    end)

    expect(Cara.AI.ChatMock, :send_message_stream, fn "", context, _opts ->
      # HERE WE CHECK IF USER MESSAGE IS PRESENT
      messages = context.messages
      roles = Enum.map(messages, & &1.role)

      send(test_pid, {:roles_in_second_call, roles})

      stream_response = %StreamResponse{
        context: context,
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("X is a great person.")],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _text -> context end, []}
    end)

    # Mock tool execution
    stub(Cara.AI.ChatMock, :execute_tool, fn _tool, _args -> {:ok, "Tool result for X"} end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Submit a message
    view
    |> form("form", chat: %{message: "Who is X?"})
    |> render_submit()

    # Wait for async processing
    :timer.sleep(300)

    # Assert roles were correct in the second call
    assert_received {:roles_in_second_call, roles}

    # We expect: system, user, assistant (tool calls), tool (results)
    assert :system in roles
    assert :user in roles
    assert :assistant in roles
    assert :tool in roles

    # Final response should be visible
    assert render(view) =~ "X is a great person."
  end
end
