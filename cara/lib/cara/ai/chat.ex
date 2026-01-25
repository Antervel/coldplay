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

  # OpenRouter models, including those from HuggingFace
  # https://openrouter.ai/docs#models
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

  @doc """
  Test if the OpenRouter API key is working properly.
  """
  def test_api_key do
    case System.get_env("OPENROUTER_API_KEY") do
      nil ->
        IO.puts("❌ OPENROUTER_API_KEY not set")
        {:error, :missing_key}

      key ->
        IO.puts("✓ OPENROUTER_API_KEY found: #{String.slice(key, 0..15)}...")

        # Try a simple request
        IO.puts("Testing API key with simple request...")

        # Use a simple OpenRouter-compatible model for testing.
        case ReqLLM.generate_text(@default_model, "Say 'test successful'") do
          {:ok, response} ->
            IO.puts("✓ API key is valid!")
            IO.puts("Response: #{ReqLLM.Response.text(response)}")
            {:ok, :valid}

          {:error, %{status: status, response_body: body}} when status in [401, 403] ->
            IO.puts("❌ API key invalid or unauthorized")
            IO.puts("Error details: #{inspect(body)}")
            IO.puts("\nTroubleshooting:")
            IO.puts("1. Go to https://openrouter.ai/keys")
            IO.puts("2. Create a NEW API key (ensure it has access to the models you want to use)")
            IO.puts("3. Check if the key has any restrictions (IP/referrer)")
            {:error, :invalid_key}

          {:error, reason} ->
            IO.puts("❌ Unexpected error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Starts an interactive chat session in the IEx console with streaming responses.

  Options:
    * `:model` - The model to use (default: #{@default_model})
    * `:system_prompt` - Custom system prompt (default: built-in)
    * `:fallback_models` - List of fallback models (default: #{inspect(@fallback_models)})
    * `:stream` - Whether to stream responses (default: true)
  """
  def start(opts \\ []) do
    # Check if API key is set
    unless System.get_env("OPENROUTER_API_KEY") do
      IO.puts("\n>> ERROR: OPENROUTER_API_KEY environment variable not set!")
      IO.puts(">> Get your OpenRouter API key at: https://openrouter.ai/keys")
      IO.puts(">> Then run: export OPENROUTER_API_KEY=your_key_here")
      IO.puts(">> Or test your key with: Cara.AI.Chat.test_api_key()\n")
      {:error, :missing_api_key}
    end

    model = Keyword.get(opts, :model, @default_model)
    system_prompt = Keyword.get(opts, :system_prompt, @system_prompt)
    fallback_models = Keyword.get(opts, :fallback_models, @fallback_models)
    stream = Keyword.get(opts, :stream, true)

    IO.puts("\n>> Starting chat session...")
    IO.puts(">> Model: #{model}")
    IO.puts(">> Streaming: #{stream}")
    IO.puts(">> Type your message (or 'quit' to exit)\n")

    # Initialize context with system message
    initial_context = Context.new([system(system_prompt)])

    chat_loop(initial_context, model, fallback_models, stream)
  end

  @doc """
  Sends a single message and returns the response without entering a loop.
  Uses streaming internally but returns the complete text.
  Useful for programmatic usage.

  ## Example

      iex> context = ReqLLM.Context.new([])
      iex> {:ok, response, new_context} = Cara.AI.Chat.send_message("Hello!", context)
  """
  def send_message(message, context, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    fallback_models = Keyword.get(opts, :fallback_models, @fallback_models)

    # Add user message to context
    updated_context = Context.append(context, user(message))

    # Generate response with streaming
    case call_llm_stream(model, updated_context, fallback_models) do
      {:ok, stream_response} ->
        # Consume the stream and accumulate text
        final_text =
          stream_response.stream
          |> Enum.reduce("", fn chunk, acc ->
            if chunk.type == :content do
              acc <> chunk.text
            else
              acc
            end
          end)

        # Add assistant response to context
        final_context = Context.append(updated_context, assistant(final_text))
        {:ok, final_text, final_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context.
  Perfect for web interfaces that need to stream responses to users.

  ## Example

      iex> context = Cara.AI.Chat.new_context()
      iex> {:ok, stream, new_context_fn} = Cara.AI.Chat.send_message_stream("Hello!", context)
      iex> text = Enum.reduce(stream, "", fn chunk, acc -> 
      ...>   IO.write(chunk)
      ...>   acc <> chunk
      ...> end)
      iex> final_context = new_context_fn.(text)

  Returns:
    * `{:ok, stream, context_builder_fn}` - Stream of text chunks and a function to build final context
    * `{:error, reason}` - Error tuple

  The context_builder_fn takes the accumulated text and returns the updated context.
  This allows you to build the context after consuming the stream.
  """
  def send_message_stream(message, context, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    fallback_models = Keyword.get(opts, :fallback_models, @fallback_models)

    # Add user message to context
    updated_context = Context.append(context, user(message))

    # Generate response with streaming
    case call_llm_stream(model, updated_context, fallback_models) do
      {:ok, stream_response} ->
        # Create a stream that only emits text content
        text_stream =
          stream_response.stream
          |> Stream.filter(fn chunk -> chunk.type == :content end)
          |> Stream.map(fn chunk -> chunk.text end)

        # Return stream and a function to build final context
        context_builder = fn final_text ->
          Context.append(updated_context, assistant(final_text))
        end

        {:ok, text_stream, context_builder}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp chat_loop(context, model, fallback_models, stream?) do
    # Get user input
    case get_user_input() do
      :quit ->
        IO.puts(">> Chat ended.\n")
        :ok

      {:ok, user_message} ->
        # Add user message to context
        updated_context = Context.append(context, user(user_message))

        # Get AI response with streaming
        case call_llm_stream(model, updated_context, fallback_models) do
          {:ok, stream_response} ->
            IO.write("Assistant: ")

            # Consume the stream and print chunks - handle errors during streaming
            result =
              try do
                final_text =
                  stream_response.stream
                  |> Enum.reduce("", fn chunk, acc ->
                    if chunk.type == :content do
                      if stream? do
                        IO.write(chunk.text)
                      end

                      acc <> chunk.text
                    else
                      acc
                    end
                  end)

                {:ok, final_text}
              rescue
                e ->
                  IO.puts("\n>> Stream error: #{inspect(e)}")
                  {:error, e}
              end

            case result do
              {:ok, final_text} ->
                if !stream? do
                  IO.write(final_text)
                end

                IO.write("\n\n")

                # Add assistant response to context and continue
                new_context = Context.append(updated_context, assistant(final_text))
                chat_loop(new_context, model, fallback_models, stream?)

              {:error, _reason} ->
                # Stream failed, don't update context
                IO.puts(">> Continuing with previous context...\n")
                chat_loop(context, model, fallback_models, stream?)
            end

          {:error, reason} ->
            IO.puts(">> Error: #{inspect(reason)}\n")
            # Continue with same context
            chat_loop(context, model, fallback_models, stream?)
        end
    end
  end

  defp get_user_input do
    input = IO.gets("You: ") |> String.trim()

    case String.downcase(input) do
      "" ->
        get_user_input()

      q when q in ["quit", "exit", "q"] ->
        :quit

      message ->
        {:ok, message}
    end
  end

  defp call_llm_stream(model, context, fallback_models) do
    # Try primary model first
    all_models = [model | fallback_models]

    try_models(all_models, context)
  end

  defp try_models([], _context) do
    {:error, "All models failed"}
  end

  defp try_models([model | rest], context) do
    # Extract just the model name if it has a provider prefix
    model_to_try =
      cond do
        String.starts_with?(model, "huggingface:") -> model
        String.contains?(model, ":") -> model
        true -> "openrouter:#{model}"
      end

    result =
      try do
        ReqLLM.stream_text(model_to_try, context.messages)
      rescue
        # Catch the exception raised by ReqLLM.stream_text
        e ->
          {:error, e}
      end

    case result do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        IO.puts(">> Model #{model_to_try} failed: #{inspect(reason)}")

        if rest != [] do
          IO.puts(">> Trying fallback model...")
          try_models(rest, context)
        else
          {:error, reason}
        end
    end
  end

  @doc """
  Creates a new chat context with an optional custom system prompt.
  """
  def new_context(system_prompt \\ @system_prompt) do
    Context.new([system(system_prompt)])
  end

  @doc """
  Returns the conversation history as a list of messages.
  """
  def get_history(context) do
    context.messages
  end

  @doc """
  Clears the conversation history while keeping the system prompt.
  """
  def reset_context(context) do
    # Keep only system messages
    system_messages = Enum.filter(context.messages, fn msg -> msg.role == :system end)
    Context.new(system_messages)
  end
end
