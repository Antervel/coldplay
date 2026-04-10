defmodule Cara.AI.ChatOrchestratorTest do
  use ExUnit.Case, async: true
  import Mox

  alias Cara.AI.ChatOrchestrator
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  setup :verify_on_exit!

  defp mock_params(caller_pid) do
    %{
      message: "Hello",
      llm_context: Context.new([]),
      caller_pid: caller_pid,
      llm_tools: [],
      chat_mod: Cara.AI.ChatMock,
      tool_usage_counts: %{},
      branch_id: "main"
    }
  end

  test "run/1 processes request and sends info to caller" do
    test_pid = self()
    params = mock_params(test_pid)

    expect(Cara.AI.ChatMock, :send_message_stream, 1, fn "Hello", _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Hi")],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, []}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:update_tool_usage_counts, %{}}
    assert_receive {:llm_chunk, "main", "Hi"}
    assert_receive {:llm_end, "main", _builder}
  end

  test "run/1 handles LLM error and retries" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests to avoid Mox.VerificationError on number of calls
    stub(Cara.AI.ChatMock, :send_message_stream, fn _msg, _ctx, _opts ->
      {:error, "API Error"}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    # We should see retrying status
    assert_receive {:llm_status, "main", "Retrying..."}
    # Wait for the eventual error after retries (though we might not want to wait for all 10)
    # The test will complete when this is received
    assert_receive {:llm_error, "main", "Error: \"API Error\""}, 5000
  end

  test "run/1 handles tool calls" do
    test_pid = self()
    params = mock_params(test_pid)

    tool_call = %ReqLLM.ToolCall{id: "call_1", type: "function", function: %{name: "calculator", arguments: "{}"}}

    # First call returns tool call
    expect(Cara.AI.ChatMock, :send_message_stream, 1, fn "Hello", _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, [tool_call]}
    end)

    # Second call (after tool execution) returns text
    expect(Cara.AI.ChatMock, :send_message_stream, 1, fn "", _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Result is 4")],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, []}
    end)

    # Mock tool execution
    stub(Cara.AI.ChatMock, :execute_tool, fn _tool, _args -> {:ok, 4} end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_status, "main", "Using calculator..."}
    assert_receive {:llm_chunk, "main", "Result is 4"}
  end

  test "run/1 handles tool limit" do
    test_pid = self()
    params = %{mock_params(test_pid) | tool_usage_counts: %{calculator: 10}}

    tool_call = %ReqLLM.ToolCall{id: "call_1", type: "function", function: %{name: "calculator", arguments: "{}"}}

    expect(Cara.AI.ChatMock, :send_message_stream, 1, fn "Hello", _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, [tool_call]}
    end)

    # Should NOT call execute_tool, instead should call send_message_stream again with limit message
    expect(Cara.AI.ChatMock, :send_message_stream, 1, fn "", _ctx, _opts ->
      # _ctx should contain the "Tool limit reached" message
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Too many tools")],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, []}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)
    assert_receive {:llm_chunk, "main", "Too many tools"}
  end

  test "run/1 handles empty response from AI" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests
    stub(Cara.AI.ChatMock, :send_message_stream, fn _msg, _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %ReqLLM.Model{model: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        # Empty stream
        stream: [],
        metadata_task: Task.async(fn -> %{} end)
      }

      {:ok, stream_response, fn _ -> :updated_context end, []}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_error, "main", "The AI did not return a response. Please try again."}, 5000
  end

  test "run/1 handles exceptions" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests
    stub(Cara.AI.ChatMock, :send_message_stream, fn _msg, _ctx, _opts ->
      raise "Crash!"
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_error, "main", "Error: Crash!"}, 5000
  end
end
