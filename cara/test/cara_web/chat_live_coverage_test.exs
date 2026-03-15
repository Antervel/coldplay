defmodule CaraWeb.ChatLiveCoverageTest do
  use CaraWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox

  alias ReqLLM.Context
  alias ReqLLM.StreamChunk
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    # Stub health check
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test", age: "10", subject: "Math"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  # Define mock
  setup :verify_on_exit!

  defp mock_model do
    %ReqLLM.Model{model: "test-model", provider: :openai}
  end

  test "enforces tool limit", %{conn: conn} do
    initial_context = Context.new([Context.system("System")])
    stub(Cara.AI.ChatMock, :new_context, fn _ -> initial_context end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Let's mock send_message_stream to return tool calls when count is high
    expect(Cara.AI.ChatMock, :send_message_stream, fn _, _, _ ->
      tc = ReqLLM.ToolCall.new("id", "calculator", "{\"expression\":\"2+2\"}")

      stream = %StreamResponse{
        context: initial_context,
        model: mock_model(),
        cancel: fn -> :ok end,
        stream: [%StreamChunk{type: :content, text: ""}],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream, fn _ -> initial_context end, [tc]}
    end)

    # We need to set the state of tool_usage_counts to 10
    :sys.replace_state(view.pid, fn state ->
      socket = state.socket
      new_socket = Phoenix.Component.assign(socket, :tool_usage_counts, %{calculator: 10})
      %{state | socket: new_socket}
    end)

    # This should trigger the "Tool limit reached" path
    expect(Cara.AI.ChatMock, :send_message_stream, fn "", context, _ ->
      # Check if "Tool limit reached" is in context
      assert Enum.any?(context.messages, fn m ->
               m.role == :tool && hd(m.content).text =~ "Tool limit reached"
             end)

      stream = %StreamResponse{
        context: context,
        model: mock_model(),
        cancel: fn -> :ok end,
        stream: [%StreamChunk{type: :content, text: "Limit reached response"}],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream, fn _ -> context end, []}
    end)

    view |> form("form", chat: %{message: "2+2"}) |> render_submit()

    :timer.sleep(200)
    assert render(view) =~ "Limit reached response"
  end

  test "format_exception_message with various exceptions", %{conn: conn} do
    initial_context = Context.new([Context.system("System")])
    stub(Cara.AI.ChatMock, :new_context, fn _ -> initial_context end)

    {:ok, view, _html} = live(conn, ~p"/chat")

    # Mock to raise a specific error
    stub(Cara.AI.ChatMock, :send_message_stream, fn _, _, _ ->
      raise %ReqLLM.Error.API.Request{status: 429, response_body: %{}}
    end)

    view |> form("form", chat: %{message: "trigger error"}) |> render_submit()
    :timer.sleep(100)
    assert render(view) =~ "The AI is busy"
  end
end
