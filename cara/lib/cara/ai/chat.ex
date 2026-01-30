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
      iex> {:ok, stream, new_context} = Cara.AI.Chat.send_message_stream("Hello!", context)
      iex> Enum.each(stream, fn chunk -> IO.write(chunk) end)
  """
  import ReqLLM.Context
  alias ReqLLM.Context

  @type chat_error :: :missing_api_key | :all_models_failed | {:model_error, term()}
  @type stream_chunk :: %{type: atom(), text: String.t()}
  @type llm_stream_response :: %{stream: Enumerable.t()}

  # OpenRouter models, including those from HuggingFace
  @default_model "openrouter:mistralai/mistral-7b-instruct-v0.2"
  @fallback_models [
    "openrouter:microsoft/phi-2",
    "openrouter:nousresearch/hermes-2-theta-llama-3-8b-gguf",
    "openrouter:qwen/qwen2-7b-instruct"
  ]

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
    * `:fallback_models` - List of fallback models (default: #{inspect(@fallback_models)})
    * `:stream` - Whether to stream responses (default: true)
  """
  @spec start(keyword()) :: :ok | {:error, chat_error()}
  def start(opts \\ []) do
    with :ok <- validate_api_key(),
         config <- build_chat_config(opts) do
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
          {:ok, String.t(), Context.t()} | {:error, chat_error()}
  def send_message(message, context, opts \\ []) do
    config = build_chat_config(opts)

    with updated_context <- add_user_message(context, message),
         {:ok, stream_response} <- call_llm_with_fallback(config, updated_context),
         final_text <- consume_stream_to_text(stream_response.stream),
         final_context <- add_assistant_message(updated_context, final_text) do
      {:ok, final_text, final_context}
    end
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context.
  Perfect for web interfaces that need to stream responses to users.

  Returns:
    * `{:ok, stream, context_builder_fn}` - Stream of text chunks and a function to build final context
    * `{:error, reason}` - Error tuple
  """
  @spec send_message_stream(String.t(), Context.t(), keyword()) ::
          {:ok, Enumerable.t(), (String.t() -> Context.t())} | {:error, chat_error()}
  def send_message_stream(message, context, opts \\ []) do
    config = build_chat_config(opts)

    with updated_context <- add_user_message(context, message),
         {:ok, stream_response} <- call_llm_with_fallback(config, updated_context) do
      text_stream = extract_text_stream(stream_response.stream)
      context_builder = fn final_text -> add_assistant_message(updated_context, final_text) end

      {:ok, text_stream, context_builder}
    end
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
      fallback_models: Keyword.get(opts, :fallback_models, @fallback_models),
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

  @spec call_llm_with_fallback(map(), Context.t()) ::
          {:ok, llm_stream_response()} | {:error, chat_error()}
  defp call_llm_with_fallback(config, context) do
    all_models = [config.model | config.fallback_models]
    try_models_sequentially(all_models, context)
  end

  @spec try_models_sequentially([String.t()], Context.t()) ::
          {:ok, llm_stream_response()} | {:error, chat_error()}
  defp try_models_sequentially([], _context) do
    {:error, :all_models_failed}
  end

  defp try_models_sequentially([model | remaining_models], context) do
    normalized_model = normalize_model_name(model)

    case attempt_model_call(normalized_model, context) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        log_model_failure(normalized_model, reason)
        handle_model_failure(remaining_models, context)
    end
  end

  @spec attempt_model_call(String.t(), Context.t()) ::
          {:ok, llm_stream_response()} | {:error, term()}
  defp attempt_model_call(model, context) do
    try do
      case ReqLLM.stream_text(model, context.messages) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, {:model_error, reason}}
      end
    rescue
      exception -> {:error, {:model_exception, exception}}
    end
  end

  @spec normalize_model_name(String.t()) :: String.t()
  defp normalize_model_name(model) do
    cond do
      String.starts_with?(model, "huggingface:") -> model
      String.contains?(model, ":") -> model
      true -> "openrouter:#{model}"
    end
  end

  @spec handle_model_failure([String.t()], Context.t()) ::
          {:ok, llm_stream_response()} | {:error, chat_error()}
  defp handle_model_failure([], _context) do
    {:error, :all_models_failed}
  end

  defp handle_model_failure(remaining_models, context) do
    IO.puts(">> Trying fallback model...")
    try_models_sequentially(remaining_models, context)
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

  defp chat_loop(context, config) do
    case get_user_input() do
      :quit ->
        IO.puts(">> Chat ended.\n")
        :ok

      {:ok, user_message} ->
        handle_user_message(user_message, context, config)
    end
  end

  defp handle_user_message(message, context, config) do
    updated_context = add_user_message(context, message)

    case call_llm_with_fallback(config, updated_context) do
      {:ok, stream_response} ->
        process_and_display_response(stream_response, updated_context, config)

      {:error, reason} ->
        print_error(reason)
        chat_loop(context, config)
    end
  end

  defp process_and_display_response(stream_response, context, config) do
    IO.write("Assistant: ")

    case consume_and_display_stream(stream_response.stream, config.stream) do
      {:ok, final_text} ->
        IO.write("\n\n")
        new_context = add_assistant_message(context, final_text)
        chat_loop(new_context, config)

      {:error, _reason} ->
        IO.puts(">> Continuing with previous context...\n")
        chat_loop(context, config)
    end
  end

  @spec consume_and_display_stream(Enumerable.t(), boolean()) ::
          {:ok, String.t()} | {:error, term()}
  defp consume_and_display_stream(stream, should_stream?) do
    try do
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
      {:ok, final_text}
    rescue
      exception ->
        IO.puts("\n>> Stream error: #{inspect(exception)}")
        {:error, exception}
    end
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

  defp print_error(reason) do
    IO.puts(">> Error: #{inspect(reason)}\n")
  end

  defp log_model_failure(model, reason) do
    IO.puts(">> Model #{model} failed: #{inspect(reason)}")
  end
end
