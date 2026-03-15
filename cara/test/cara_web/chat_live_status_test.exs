defmodule CaraWeb.ChatLiveStatusTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    # Stub health check
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

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

  test "shows 'Thinking...' immediately after submitting", %{conn: conn} do
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

    # We use a long-running mock to capture the status
    parent = self()

    stub(Cara.AI.ChatMock, :send_message_stream, fn _msg, _ctx, _opts ->
      send(parent, :mock_called)
      # Wait a bit so the LiveView doesn't finish immediately
      Process.sleep(200)

      stream_response = %StreamResponse{
        context: %ReqLLM.Context{messages: []},
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> Context.new([]) end, []}
    end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Submit message
    view |> form("form", chat: %{message: "Hi"}) |> render_submit()

    # Should show thinking status
    assert render(view) =~ "Thinking..."
    assert_receive :mock_called
  end

  test "shows 'Using [tool]...' when tools are being called", %{conn: conn} do
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

    # 1. First call returns a tool call
    # 2. Second call returns final text
    parent = self()

    expect(Cara.AI.ChatMock, :send_message_stream, fn "Who is X?", context, _opts ->
      send(parent, :first_call)
      tool_calls = [ReqLLM.ToolCall.new("call_1", "wikipedia_search", "{\"query\": \"X\"}")]

      stream_response = %StreamResponse{
        context: context,
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> context end, tool_calls}
    end)

    expect(Cara.AI.ChatMock, :send_message_stream, fn "", context, _opts ->
      send(parent, :second_call)
      # Wait to let the UI show the status
      Process.sleep(200)
      stream = [ReqLLM.StreamChunk.text("Done!")]

      stream_response = %StreamResponse{
        context: context,
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: stream,
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> context end, []}
    end)

    stub(Cara.AI.ChatMock, :execute_tool, fn _tool, _args -> {:ok, "Result"} end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    view |> form("form", chat: %{message: "Who is X?"}) |> render_submit()

    assert_receive :first_call
    # After first call, tool status should be updated
    Process.sleep(50)
    assert render(view) =~ "Using wikipedia_search..."

    assert_receive :second_call
    # After second call starts streaming, status should be cleared
    Process.sleep(300)
    refute render(view) =~ "Using wikipedia_search..."
    assert render(view) =~ "Done!"
  end

  test "clears status on error", %{conn: conn} do
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

    stub(Cara.AI.ChatMock, :send_message_stream, fn _msg, _ctx, _opts ->
      {:error, "Something went wrong"}
    end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    view |> form("form", chat: %{message: "Error test"}) |> render_submit()

    # Initially it might show "Thinking..." but error should clear it
    Process.sleep(100)
    refute render(view) =~ "Thinking..."
    assert render(view) =~ "Something went wrong"
  end
end
