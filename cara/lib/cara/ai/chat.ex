defmodule Cara.AI.Chat do
  @moduledoc """
  Interactive chat module using ReqLLM with OpenRouter (accessing HuggingFace models) and streaming support.

  Setup:
  1. Get an OpenRouter API key from https://openrouter.ai/keys
  2. Set environment variable: `export OPENROUTER_API_KEY=your_key_here`
  3. Start chatting: `Cara.AI.Chat.start()`

  Usage from iex:

      iex> Cara.AI.Chat.start()
      >> Starting chat session...
      >> Type your message (or 'quit' to exit)
      You: Hello!
      Assistant: Hi there! How can I help you today?
      You: quit
      >> Chat ended.

  For web interfaces, use the streaming version:

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, stream, context_builder} = Cara.AI.Chat.send_message_stream("Hello!", context)
      iex> Enum.each(stream, fn chunk -> IO.write(chunk) end)
  """
  import ReqLLM.Context
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  @type stream_chunk :: %{type: atom(), text: String.t()}

  @default_model "openrouter:mistralai/mistral-7b-instruct-v0.2"

  @system_prompt """
  You are a helpful, friendly AI assistant. Engage in natural conversation,
  answer questions clearly, and be concise unless asked for detailed explanations.
  """

  ## Public API

  @doc """
  Starts an interactive chat session in the IEx console with streaming responses.

  Options:
    * `:model` - The model to use (default: #{@default_model})
    * `:system_prompt` - Custom system prompt (default: built-in)
    * `:stream` - Whether to stream responses (default: true)
  """
  @spec start(keyword()) :: :ok | {:error, :missing_api_key}
  def start(opts \\ []) do
    with :ok <- validate_api_key() do
      config = build_chat_config(opts)
      print_chat_header(config)
      initial_context = new_context(config.system_prompt)
      chat_loop(initial_context, config)
    end
  end

  @doc """
  Sends a single message and returns the response without entering a loop.
  Uses streaming internally but returns the complete text.
  """
  @spec send_message(String.t(), Context.t(), keyword()) ::
          {:ok, String.t(), Context.t()}
  def send_message(message, context, opts \\ []) do
    config = build_chat_config(opts)
    updated_context = add_user_message(context, message)

    {:ok, stream_response} = call_llm(config.model, updated_context)
    final_text = consume_stream_to_text(stream_response.stream)
    final_context = add_assistant_message(updated_context, final_text)

    {:ok, final_text, final_context}
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context.
  Perfect for web interfaces that need to stream responses to users.

  Returns:
    * `{:ok, stream, context_builder_fn}` - Stream of text chunks and a function to build final context
  """
  @spec send_message_stream(String.t(), Context.t(), keyword()) ::
          {:ok, Enumerable.t(), (String.t() -> Context.t())}
  def send_message_stream(message, context, opts \\ []) do
    config = build_chat_config(opts)
    updated_context = add_user_message(context, message)

    {:ok, stream_response} = call_llm(config.model, updated_context)
    text_stream = extract_text_stream(stream_response.stream)
    context_builder = fn final_text -> add_assistant_message(updated_context, final_text) end

    {:ok, text_stream, context_builder}
  end

  @doc """
  Creates a new chat context with an optional custom system prompt.
  """
  @spec new_context(String.t()) :: Context.t()
  def new_context(system_prompt \\ @system_prompt) do
    Context.new([system(system_prompt)])
  end

  @doc """
  Returns the conversation history as a list of messages.
  """
  @spec get_history(Context.t()) :: list()
  def get_history(context) do
    context.messages
  end

  @doc """
  Clears the conversation history while keeping the system prompt.
  """
  @spec reset_context(Context.t()) :: Context.t()
  def reset_context(context) do
    system_messages = Enum.filter(context.messages, fn msg -> msg.role == :system end)
    Context.new(system_messages)
  end

  ## Configuration Management

  defp build_chat_config(opts) do
    %{
      model: Keyword.get(opts, :model, @default_model),
      system_prompt: Keyword.get(opts, :system_prompt, @system_prompt),
      stream: Keyword.get(opts, :stream, true)
    }
  end

  ## Validation

  @spec validate_api_key() :: :ok | {:error, :missing_api_key}
  defp validate_api_key do
    if System.get_env("OPENROUTER_API_KEY") do
      :ok
    else
      print_api_key_error()
      {:error, :missing_api_key}
    end
  end

  ## Context Management

  @spec add_user_message(Context.t(), String.t()) :: Context.t()
  defp add_user_message(context, message) do
    Context.append(context, user(message))
  end

  @spec add_assistant_message(Context.t(), String.t()) :: Context.t()
  defp add_assistant_message(context, message) do
    Context.append(context, assistant(message))
  end

  ## LLM Communication

  @spec call_llm(String.t(), Context.t()) :: {:ok, StreamResponse.t()} | {:error, term()}
  defp call_llm(model, context) do
    normalized_model = normalize_model_name(model)
    ReqLLM.stream_text(normalized_model, context.messages)
  end

  @spec normalize_model_name(String.t()) :: String.t()
  defp normalize_model_name(model) do
    cond do
      String.starts_with?(model, "huggingface:") -> model
      String.contains?(model, ":") -> model
      true -> "openrouter:#{model}"
    end
  end

  ## Stream Processing

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

  ## Interactive Chat Loop

  @spec chat_loop(Context.t(), map()) :: :ok
  defp chat_loop(context, config) do
    case get_user_input() do
      :quit ->
        IO.puts(">> Chat ended.\n")
        :ok

      {:ok, user_message} ->
        handle_user_message(user_message, context, config)
    end
  end

  @spec handle_user_message(String.t(), Context.t(), map()) :: :ok | no_return()
  defp handle_user_message(message, context, config) do
    updated_context = add_user_message(context, message)
    {:ok, stream_response} = call_llm(config.model, updated_context)
    process_and_display_response(stream_response, updated_context, config)
  end

  @spec process_and_display_response(StreamResponse.t(), Context.t(), map()) :: :ok
  defp process_and_display_response(stream_response, context, config) do
    IO.write("Assistant: ")

    final_text = consume_and_display_stream(stream_response.stream, config.stream)
    IO.write("\n\n")

    new_context = add_assistant_message(context, final_text)
    chat_loop(new_context, config)
  end

  @spec consume_and_display_stream(Enumerable.t(), boolean()) :: String.t()
  defp consume_and_display_stream(stream, should_stream?) do
    final_text =
      Enum.reduce(stream, "", fn chunk, acc ->
        if content_chunk?(chunk) do
          if should_stream?, do: IO.write(chunk.text)
          acc <> chunk.text
        else
          acc
        end
      end)

    if !should_stream?, do: IO.write(final_text)
    final_text
  end

  ## User Input

  @spec get_user_input() :: :quit | {:ok, String.t()}
  defp get_user_input do
    input = IO.gets("You: ") |> String.trim()

    cond do
      input == "" -> get_user_input()
      quit_command?(input) -> :quit
      true -> {:ok, input}
    end
  end

  @spec quit_command?(String.t()) :: boolean()
  defp quit_command?(input) do
    String.downcase(input) in ["quit", "exit", "q"]
  end

  ## Output Helpers

  defp print_chat_header(config) do
    IO.puts("\n>> Starting chat session...")
    IO.puts(">> Model: #{config.model}")
    IO.puts(">> Streaming: #{config.stream}")
    IO.puts(">> Type your message (or 'quit' to exit)\n")
  end

  defp print_api_key_error do
    IO.puts("\n>> ERROR: OPENROUTER_API_KEY environment variable not set!")
    IO.puts(">> Get your OpenRouter API key at: https://openrouter.ai/keys")
    IO.puts(">> Then run: export OPENROUTER_API_KEY=your_key_here\n")
  end
end
