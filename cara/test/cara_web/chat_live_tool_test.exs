defmodule CaraWeb.ChatLiveToolTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias ReqLLM.Context
  alias ReqLLM.StreamResponse
  import Cara.Test.StreamResponseHelper

  setup %{conn: conn} do
    # Stub health check
    stub(Cara.AI.ChatMock, :health_check, fn _opts -> :ok end)

    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  # Define mock
  setup :verify_on_exit!

  test "handles tool calls and preserves user message in context", %{conn: conn} do
    initial_context = Context.new([Context.system("You are helpful")])
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> initial_context end)

    test_pid = self()

    # 1. First call: user message "Who is X?", returns a tool call
    # 2. Second call: empty message, returns the final answer

    expect(Cara.AI.ChatClientMock, :send_message_stream, fn ctx, _opts ->
      tool_calls = [
        %ReqLLM.ToolCall{
          id: "call_1",
          type: "function",
          function: %{name: "wikipedia_search", arguments: Jason.encode!(%{"query" => "X"})}
        }
      ]

      {:ok,
       %BranchedLLM.LLM.StreamResult.ToolCallResult{
         tool_calls: tool_calls,
         context: ctx,
         metadata_handle: start_metadata_handle()
       }}
    end)

    expect(Cara.AI.ChatClientMock, :send_message_stream, fn ctx, _opts ->
      messages = ctx.messages
      roles = Enum.map(messages, & &1.role)

      send(test_pid, {:roles_in_second_call, roles})

      stream_response = %StreamResponse{
        context: %ReqLLM.Context{messages: []},
        model: %LLMDB.Model{id: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("X is a great person.")],
        metadata_handle: start_metadata_handle()
      }

      {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
    end)

    # Mock tool execution
    stub(Cara.AI.ChatClientMock, :execute_tool, fn _tool, _args -> {:ok, "Tool result for X"} end)

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
