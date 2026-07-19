defmodule BranchedLLM.ChatOrchestratorTest do
  use ExUnit.Case, async: true
  import Mox

  alias BranchedLLM.ChatOrchestrator
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse
  import Cara.Test.StreamResponseHelper

  setup :verify_on_exit!

  defp mock_params(caller_pid) do
    %{
      llm_context: Context.new([]),
      on_event: fn event -> send(caller_pid, event) end,
      llm_tools: [],
      chat_mod: Cara.AI.ChatClientMock,
      tool_usage_counts: %{},
      branch_id: "main"
    }
  end

  test "run/1 processes request and sends info to live_view" do
    test_pid = self()
    params = mock_params(test_pid)

    expect(Cara.AI.ChatClientMock, :send_message_stream, 1, fn _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %LLMDB.Model{id: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Hi")],
        metadata_handle: start_metadata_handle()
      }

      {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:update_tool_usage_counts, %{}}
    assert_receive {:llm_chunk, "main", "Hi"}
    assert_receive {:llm_end, "main", _}
  end

  test "run/1 handles LLM error and retries" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests to avoid Mox.VerificationError on number of calls
    stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
      {:error, "API Error"}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    # We should see retrying status (retries happen with 100ms backoff, so wait longer)
    assert_receive {:llm_status, "main", "Retrying..."}, 5000
    # Wait for the eventual error after retries (though we might not want to wait for all 10)
    # The test will complete when this is received
    assert_receive {:llm_error, "main", "Error: \"API Error\""}, 5000
  end

  test "run/1 handles tool calls" do
    test_pid = self()
    params = mock_params(test_pid)

    tool_call = %ReqLLM.ToolCall{id: "call_1", type: "function", function: %{name: "calculator", arguments: "{}"}}

    # First call returns tool call
    expect(Cara.AI.ChatClientMock, :send_message_stream, 1, fn _ctx, _opts ->
      {:ok,
       %BranchedLLM.LLM.StreamResult.ToolCallResult{
         tool_calls: [tool_call],
         context: Context.new([]),
         metadata_handle: start_metadata_handle()
       }}
    end)

    # Second call (after tool execution) returns text
    expect(Cara.AI.ChatClientMock, :send_message_stream, 1, fn _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %LLMDB.Model{id: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Result is 4")],
        metadata_handle: start_metadata_handle()
      }

      {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
    end)

    # Mock tool execution
    stub(Cara.AI.ChatClientMock, :execute_tool, fn _tool, _args -> {:ok, 4} end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_status, "main", "Using calculator..."}
    assert_receive {:llm_chunk, "main", "Result is 4"}
  end

  test "run/1 handles tool limit" do
    test_pid = self()
    params = %{mock_params(test_pid) | tool_usage_counts: %{calculator: 10}}

    tool_call = %ReqLLM.ToolCall{id: "call_1", type: "function", function: %{name: "calculator", arguments: "{}"}}

    expect(Cara.AI.ChatClientMock, :send_message_stream, 1, fn _ctx, _opts ->
      {:ok,
       %BranchedLLM.LLM.StreamResult.ToolCallResult{
         tool_calls: [tool_call],
         context: Context.new([]),
         metadata_handle: start_metadata_handle()
       }}
    end)

    # Should NOT call execute_tool, instead should call send_message_stream again with limit message
    expect(Cara.AI.ChatClientMock, :send_message_stream, 1, fn _ctx, _opts ->
      stream_response = %StreamResponse{
        context: Context.new([]),
        model: %LLMDB.Model{id: "test-model", provider: :openai},
        cancel: fn -> :ok end,
        stream: [ReqLLM.StreamChunk.text("Too many tools")],
        metadata_handle: start_metadata_handle()
      }

      {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)
    assert_receive {:llm_chunk, "main", "Too many tools"}
  end

  test "run/1 handles empty response from AI" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests
    stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
      {:ok, %BranchedLLM.LLM.StreamResult.EmptyResult{}}
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_error, "main", "The AI did not return a response. Please try again."}, 5000
  end

  test "run/1 handles exceptions" do
    test_pid = self()
    params = mock_params(test_pid)

    # Use stub for retry tests
    stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
      raise "Crash!"
    end)

    {:ok, _pid} = ChatOrchestrator.run(params)

    assert_receive {:llm_error, "main", "Crash!"}, 5000
  end
end
