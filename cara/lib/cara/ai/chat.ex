defmodule Cara.AI.Chat do
  @moduledoc """
  Core chat functionality for interacting with LLM APIs.

  Handles message sending, streaming, and conversation context management.
  """
  import ReqLLM.Context
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  @behaviour Cara.AI.ChatBehaviour
  @default_model "openrouter:mistralai/mistral-7b-instruct-v0.2"
  @type stream_chunk :: %{type: atom(), text: String.t()}

  @system_prompt """
  You are a helpful, friendly AI assistant. Engage in natural conversation,
  answer questions clearly, and be concise unless asked for detailed explanations.
  """

  ## Public API

  @doc """
  Sends a single message and returns the response without entering a loop.
  Uses streaming internally but returns the complete text.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, response, new_context} = Cara.AI.Chat.send_message("Hello!", context)

  ## Options

    * `:model` - The model to use (default: #{@default_model})
  """
  @spec send_message(String.t(), Context.t(), keyword()) ::
          {:ok, String.t(), Context.t()}
  def send_message(message, context, opts \\ []) do
    config = build_config(opts)
    updated_context = add_user_message(context, message)

    {:ok, stream_response} = call_llm(config.model, updated_context)
    final_text = consume_stream_to_text(stream_response.stream)
    final_context = add_assistant_message(updated_context, final_text)

    {:ok, final_text, final_context}
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context.
  Perfect for web interfaces that need to stream responses to users.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, stream, context_builder} = Cara.AI.Chat.send_message_stream("Hello!", context)
      iex> Enum.each(stream, fn chunk -> IO.write(chunk) end)

  ## Returns

    * `{:ok, stream, context_builder_fn}` - Stream of text chunks and a function to build final context

  ## Options

    * `:model` - The model to use (default: #{@default_model})
  """
  @spec send_message_stream(String.t(), Context.t(), keyword()) ::
          {:ok, Enumerable.t(), (String.t() -> Context.t())}
  def send_message_stream(message, context, opts \\ []) do
    config = build_config(opts)
    updated_context = add_user_message(context, message)

    {:ok, stream_response} = call_llm(config.model, updated_context)
    text_stream = extract_text_stream(stream_response.stream)
    context_builder = fn final_text -> add_assistant_message(updated_context, final_text) end

    {:ok, text_stream, context_builder}
  end

  @doc """
  Creates a new chat context with an optional custom system prompt.

  ## Examples

      iex> context = Cara.AI.Chat.new_context()
      iex> context = Cara.AI.Chat.new_context("You are a helpful coding assistant")
  """
  @spec new_context(String.t()) :: Context.t()
  def new_context(system_prompt \\ @system_prompt) do
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
  def default_model, do: @default_model

  @doc """
  Returns the default system prompt.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt, do: @system_prompt

  ## Private Functions

  defp build_config(opts) do
    %{
      model: Keyword.get(opts, :model, @default_model)
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

  @spec call_llm(String.t(), Context.t()) :: {:ok, StreamResponse.t()} | {:error, term()}
  defp call_llm(model, context) do
    ReqLLM.stream_text(model, context.messages)
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
end
