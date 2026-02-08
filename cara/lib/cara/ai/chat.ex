defmodule Cara.AI.Chat do
  @moduledoc """
  Core chat functionality for interacting with LLM APIs.

  Handles message sending, streaming, and conversation context management.
  """
  import ReqLLM.Context
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
          {:ok, Enumerable.t(), (String.t() -> Context.t()), list()}
  def send_message_stream(message, context, opts \\ []) do
    config = build_config(opts)
    updated_context = add_user_message(context, message)

    case call_llm(config.model, updated_context, config.tools) do
      {:ok, stream_response, tool_calls} ->
        text_stream = extract_text_stream(stream_response.stream)
        context_builder = fn final_text -> add_assistant_message(updated_context, final_text) end
        {:ok, text_stream, context_builder, tool_calls}

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
    if Enum.empty?(tools) do
      # No tools provided, just stream text directly
      case ReqLLM.stream_text(model, context.messages, tools: tools) do
        {:ok, stream_response} -> {:ok, stream_response, []}
        {:error, reason} -> {:error, reason}
      end
    else
      # Tools are provided, first attempt to get tool calls using generate_text
      case ReqLLM.generate_text(model, context.messages, tools: tools) do
        {:ok, response} -> handle_tool_check_response(response, model, context, tools)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp handle_tool_check_response(response, model, context, tools) do
    tool_calls = ReqLLM.Response.tool_calls(response)

    if Enum.empty?(tool_calls) do
      # No tool calls, proceed with streaming the text response
      case ReqLLM.stream_text(model, context.messages, tools: tools) do
        {:ok, stream_response} -> {:ok, stream_response, []}
        {:error, reason} -> {:error, reason}
      end
    else
      # Tool calls found
      dummy_stream_response = %StreamResponse{
        stream: Stream.cycle([""]),
        context: response.context,
        model: response.model,
        cancel: fn -> :ok end,
        metadata_task: Task.async(fn -> {:ok, %{}} end)
      }

      {:ok, dummy_stream_response, tool_calls}
    end
  end

  @spec extract_text_stream(Enumerable.t()) :: Enumerable.t()
  defp extract_text_stream(stream) do
    stream
    |> Stream.filter(&content_chunk?/1)
    |> Stream.map(& &1.text)
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
