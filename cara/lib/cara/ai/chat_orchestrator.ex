defmodule Cara.AI.ChatOrchestrator do
  @moduledoc """
  Orchestrates the LLM request/response lifecycle, including tool calls and streaming.
  """
  use Retry
  require Logger

  alias Cara.AI.LLMErrorFormatter
  alias Cara.AI.ToolHandler
  alias ReqLLM.Context

  @type llm_call_params :: %{
          message: String.t(),
          llm_context: ReqLLM.Context.t(),
          live_view_pid: pid(),
          llm_tools: list(),
          chat_mod: module(),
          tool_usage_counts: map()
        }

  @doc """
  Starts the LLM request process in a separate task.
  """
  @spec run(llm_call_params()) :: {:ok, pid()}
  def run(params) do
    Task.start(fn ->
      retry with: constant_backoff(100) |> Stream.take(10) do
        process_llm_request(params)
      end
    end)
  end

  @spec process_llm_request(llm_call_params()) :: :ok | :retry
  defp process_llm_request(
         %{
           message: message,
           llm_context: llm_context,
           live_view_pid: live_view_pid,
           llm_tools: llm_tools,
           chat_mod: chat_mod
         } = llm_call_params
       ) do
    case chat_mod.send_message_stream(message, llm_context, tools: llm_tools) do
      {:ok, %ReqLLM.StreamResponse{} = stream_response, llm_context_builder, tool_calls} ->
        handle_llm_stream_response(
          stream_response,
          llm_context_builder,
          tool_calls,
          llm_call_params
        )

      {:error, reason} ->
        send(live_view_pid, {:llm_error, "Error: #{inspect(reason)}"})
        :error
    end
  rescue
    exception ->
      error_message = LLMErrorFormatter.format(exception)
      send(live_view_pid, {:llm_error, error_message})
      :error
  end

  @spec handle_llm_stream_response(
          ReqLLM.StreamResponse.t(),
          (String.t() -> ReqLLM.Context.t()),
          list(),
          llm_call_params()
        ) :: :ok | :retry
  defp handle_llm_stream_response(
         stream_response,
         llm_context_builder,
         tool_calls,
         %{
           live_view_pid: live_view_pid,
           tool_usage_counts: tool_usage_counts
         } = llm_call_params
       ) do
    if Enum.empty?(tool_calls) do
      # No tool calls, process the stream normally
      if process_stream(stream_response, live_view_pid, llm_context_builder, tool_usage_counts) do
        :ok
      else
        send(live_view_pid, {:llm_error, "The AI did not return a response. Please try again."})
        :error
      end
    else
      # Tool calls found, execute them and recursively call LLM with results
      updated_llm_call_params = %{llm_call_params | llm_context: stream_response.context}
      next_llm_call_params = handle_tool_call_execution(tool_calls, updated_llm_call_params)
      process_llm_request(%{next_llm_call_params | message: ""})
    end
  end

  @spec handle_tool_call_execution(list(), llm_call_params()) :: llm_call_params()
  defp handle_tool_call_execution(
         tool_calls,
         %{
           llm_context: llm_context,
           llm_tools: llm_tools,
           chat_mod: chat_mod,
           tool_usage_counts: tool_usage_counts,
           live_view_pid: live_view_pid
         } = llm_call_params
       ) do
    tool_names = Enum.map_join(tool_calls, ", ", &ReqLLM.ToolCall.name/1)
    send(live_view_pid, {:llm_status, "Using #{tool_names}..."})

    {tool_calls_to_execute, tool_results_for_limited_tools, new_tool_usage_counts} =
      Enum.reduce(tool_calls, {[], [], tool_usage_counts}, fn tool_call, {exec_acc, limited_acc, counts_acc} ->
        tool_name = ReqLLM.ToolCall.name(tool_call)
        tool_name_atom = String.to_atom(tool_name)
        current_count = Map.get(counts_acc, tool_name_atom, 0)

        if current_count < 10 do
          {[tool_call | exec_acc], limited_acc, Map.put(counts_acc, tool_name_atom, current_count + 1)}
        else
          tool_result = Context.tool_result(tool_call.id, "Tool limit reached. Summarize with what you have")
          {exec_acc, [tool_result | limited_acc], counts_acc}
        end
      end)

    tool_calls_to_execute = Enum.reverse(tool_calls_to_execute)
    tool_results_for_limited_tools = Enum.reverse(tool_results_for_limited_tools)

    llm_context_after_tool_handling =
      if Enum.empty?(tool_calls_to_execute) do
        # If no tools are executed, just append the original tool calls to the context
        Context.append(llm_context, Context.assistant("", tool_calls: tool_calls))
      else
        # Execute allowed tools and get updated context
        llm_context_with_assistant_tool_calls =
          Context.append(llm_context, Context.assistant("", tool_calls: tool_calls_to_execute))

        ToolHandler.handle_tool_calls(
          tool_calls_to_execute,
          llm_context_with_assistant_tool_calls,
          llm_tools,
          chat_mod
        )
      end

    updated_llm_context =
      Enum.reduce(tool_results_for_limited_tools, llm_context_after_tool_handling, fn tr, acc ->
        Context.append(acc, tr)
      end)

    %{llm_call_params | llm_context: updated_llm_context, tool_usage_counts: new_tool_usage_counts}
  end

  @spec process_stream(
          ReqLLM.StreamResponse.t(),
          pid(),
          (String.t() -> ReqLLM.Context.t()),
          map()
        ) :: boolean()
  defp process_stream(stream_response, live_view_pid, llm_context_builder, tool_usage_counts) do
    send(live_view_pid, {:update_tool_usage_counts, tool_usage_counts})

    start_time = :erlang.monotonic_time(:millisecond)

    sent_any_chunks =
      stream_response
      |> ReqLLM.StreamResponse.tokens()
      |> Enum.reduce_while(false, fn chunk, _acc ->
        send(live_view_pid, {:llm_chunk, chunk})
        {:cont, true}
      end)

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("LLM streaming of answer took #{end_time - start_time}ms")

    metadata = Task.await(stream_response.metadata_task)
    Logger.info("LLM stream complete metadata: #{inspect(metadata)}")

    if sent_any_chunks do
      send(live_view_pid, {:llm_end, llm_context_builder})
    end

    sent_any_chunks
  end
end
