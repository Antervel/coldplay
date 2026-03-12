defmodule Cara.AI.Chat do
  @moduledoc """
  Core chat functionality for interacting with LLM APIs.

  Handles message sending, streaming, and conversation context management.
  """
  import ReqLLM.Context

  require Logger

  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  @behaviour Cara.AI.ChatBehaviour
  @type stream_chunk :: %{type: atom(), text: String.t()}

  ## Public API

  @doc """
  Sends a single message and returns the response without entering a loop.
  Uses streaming internally but returns the complete text.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, response, new_context} = Cara.AI.Chat.send_message("Hello!", context)

  ## Options

    * `:model` - The model to use (defaults to the model specified in the application config).
  """
  @spec send_message(String.t(), Context.t(), keyword()) ::
          {:ok, String.t(), Context.t()}
  def send_message(message, context, opts \\ []) do
    config = build_config(opts)
    updated_context = add_user_message(context, message)

    {:ok, stream_response, _tool_calls} = call_llm(config.model, updated_context, config.tools)
    final_text = consume_stream_to_text(stream_response.stream)
    final_context = add_assistant_message(updated_context, final_text)

    {:ok, final_text, final_context}
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context,
  and any tool calls made by the LLM.
  Perfect for web interfaces that need to stream responses to users and handle tools.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, stream, context_builder, tool_calls} = Cara.AI.Chat.send_message_stream("Hello!", context, tools: [some_tool()])
      iex> Enum.each(stream, fn chunk -> IO.write(chunk) end)

  ## Returns

    * `{:ok, stream, context_builder_fn, tool_calls}` - Stream of text chunks, a function to build final context, and a list of tool calls

  ## Options

    * `:model` - The model to use (defaults to the model specified in the application config).
    * `:tools` - A list of `ReqLLM.Tool` structs to provide to the LLM.
  """
  @spec send_message_stream(String.t(), Context.t(), keyword()) ::
          {:ok, ReqLLM.StreamResponse.t(), (String.t() -> Context.t()), list()} | {:error, term()}
  def send_message_stream(message, context, opts \\ []) do
    config = build_config(opts)

    updated_context =
      if message != nil and message != "" do
        add_user_message(context, message)
      else
        context
      end

    case call_llm(config.model, updated_context, config.tools) do
      {:ok, stream_response, tool_calls} ->
        context_builder = fn final_text -> add_assistant_message(updated_context, final_text) end
        {:ok, stream_response, context_builder, tool_calls}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new chat context with an optional custom system prompt.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> context = Cara.AI.Chat.new_context("You are a helpful coding assistant")
  """
  @spec new_context(String.t()) :: Context.t()
  def new_context(system_prompt) do
    Context.new([system(system_prompt)])
  end

  @doc """
  Returns the conversation history as a list of messages.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> history = Cara.AI.Chat.get_history(context)
      iex> length(history)
      1
  """
  @spec get_history(Context.t()) :: list()
  def get_history(context) do
    context.messages
  end

  @doc """
  Clears the conversation history while keeping the system prompt.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> context = Cara.AI.Chat.reset_context(context)
  """
  @spec reset_context(Context.t()) :: Context.t()
  def reset_context(context) do
    system_messages = Enum.filter(context.messages, fn msg -> msg.role == :system end)
    Context.new(system_messages)
  end

  @doc """
  Returns the default model string.
  """
  @spec default_model() :: String.t()
  def default_model do
    Application.get_env(:cara, :ai_model, "openrouter:mistralai/mistral-7b-instruct-v0.2")
  end

  ## Private Functions

  defp build_config(opts) do
    %{
      model: Keyword.get(opts, :model, default_model()),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  @spec add_user_message(Context.t(), String.t()) :: Context.t()
  defp add_user_message(context, message) do
    Context.append(context, user(message))
  end

  @spec add_assistant_message(Context.t(), String.t()) :: Context.t()
  defp add_assistant_message(context, message) do
    Context.append(context, assistant(message))
  end

  @spec call_llm(String.t(), Context.t(), list()) ::
          {:ok, StreamResponse.t(), list()} | {:error, term()}
  defp call_llm(model, context, tools) do
    Logger.info("LLM call_llm starting with context: #{inspect(context)}")
    start_time = :erlang.monotonic_time(:millisecond)

    result =
      case ReqLLM.stream_text(model, context.messages, tools: tools) do
        {:ok, stream_response} ->
          if Enum.empty?(tools) do
            {:ok, stream_response, []}
          else
            handle_stream_for_tools(stream_response)
          end

        {:error, reason} ->
          {:error, reason}
      end

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("LLM call_llm(model: #{model}, tools: #{length(tools)}) took #{end_time - start_time}ms")
    result
  end

  # Peeks at the stream to see if the LLM is calling a tool or just talking.
  defp handle_stream_for_tools(%StreamResponse{stream: stream} = stream_response) do
    # We take chunks until we see a tool call or content with text.
    case consume_until_intent(stream) do
      {:tool_call, consumed_chunks, remaining_stream} ->
        # It's a tool call! Consume the whole stream to get all arguments.
        all_chunks = consumed_chunks ++ Enum.to_list(remaining_stream)
        tool_calls = extract_tool_calls_from_chunks(all_chunks)

        # We need to provide a dummy stream because the original one is consumed
        {:ok, dummy_stream_response(stream_response), tool_calls}

      {:content, consumed_chunks, remaining_stream} ->
        # It's content (text). Prepend the chunks we took and return as a normal stream.
        new_stream = Stream.concat(consumed_chunks, remaining_stream)
        {:ok, %{stream_response | stream: new_stream}, []}

      {:empty, _consumed_chunks} ->
        # Empty stream
        {:ok, stream_response, []}
    end
  end

  defp consume_until_intent(stream) do
    Enum.reduce_while(stream, {[], stream}, fn chunk, {acc, _} ->
      cond do
        chunk.type == :tool_call ->
          {:halt, {:tool_call, Enum.reverse([chunk | acc]), stream}}

        chunk.type == :content and (chunk.text != nil and chunk.text != "") ->
          {:halt, {:content, Enum.reverse([chunk | acc]), stream}}

        true ->
          # Keep looking (meta chunks, empty content chunks, etc.)
          {:cont, {[chunk | acc], stream}}
      end
    end)
    |> case do
      {acc, _} -> {:empty, Enum.reverse(acc)}
      result -> result
    end
  end

  defp extract_tool_calls_from_chunks(chunks) do
    base_calls = Enum.filter(chunks, fn chunk -> Map.get(chunk, :type) == :tool_call end)
    fragments = extract_fragments(chunks)

    # Merge and deduplicate by ID
    base_calls
    |> Enum.map(fn call -> build_tool_call(call, fragments) end)
    |> Enum.uniq_by(fn tc -> tc.id end)
  end

  defp extract_fragments(chunks) do
    chunks
    |> Enum.filter(fn chunk ->
      Map.get(chunk, :type) == :meta and
        match?(%{tool_call_args: %{index: _}}, Map.get(chunk, :metadata, %{}))
    end)
    |> Enum.group_by(fn chunk ->
      meta = Map.get(chunk, :metadata, %{})
      args = Map.get(meta, :tool_call_args, %{})
      Map.get(args, :index)
    end)
    |> Map.new(fn {idx, meta_chunks} ->
      json =
        Enum.map_join(meta_chunks, "", fn chunk ->
          meta = Map.get(chunk, :metadata, %{})
          args = Map.get(meta, :tool_call_args, %{})
          Map.get(args, :fragment, "")
        end)

      {idx, json}
    end)
  end

  defp build_tool_call(call, fragments) do
    metadata = Map.get(call, :metadata, %{})
    index = Map.get(metadata, :index) || Map.get(call, :index)
    id = Map.get(metadata, :id) || Map.get(call, :id)
    name = Map.get(call, :name) || Map.get(metadata, :name)

    arguments_json =
      case Map.get(fragments, index) do
        nil ->
          extract_arguments_from_call(call, metadata)

        json ->
          json
      end

    ReqLLM.ToolCall.new(id, name, arguments_json)
  end

  defp extract_arguments_from_call(call, metadata) do
    call_args = Map.get(call, :arguments) || Map.get(metadata, :arguments)

    cond do
      is_binary(call_args) -> call_args
      is_map(call_args) -> Jason.encode!(call_args)
      true -> "{}"
    end
  end

  defp dummy_stream_response(%StreamResponse{context: context, model: model}) do
    %StreamResponse{
      stream: [%ReqLLM.StreamChunk{type: :content, text: ""}],
      context: context,
      model: model,
      cancel: fn -> :ok end,
      metadata_task: Task.async(fn -> %{} end)
    }
  end

  @spec consume_stream_to_text(Enumerable.t()) :: String.t()
  defp consume_stream_to_text(stream) do
    stream
    |> Enum.reduce("", &accumulate_text_chunk/2)
  end

  @spec accumulate_text_chunk(stream_chunk(), String.t()) :: String.t()
  defp accumulate_text_chunk(chunk, acc) do
    if content_chunk?(chunk) do
      acc <> chunk.text
    else
      acc
    end
  end

  @spec content_chunk?(stream_chunk()) :: boolean()
  defp content_chunk?(chunk), do: chunk.type == :content

  @doc """
  Executes a given tool with the provided arguments.
  """
  @spec execute_tool(ReqLLM.Tool.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(tool, args) do
    ReqLLM.Tool.execute(tool, args)
  end
end
