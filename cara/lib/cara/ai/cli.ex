defmodule Cara.AI.CLI do
  @moduledoc """
  Interactive command-line interface for chatting with AI models.

  Setup:
  1. Get an OpenRouter API key from https://openrouter.ai/keys
  2. Set environment variable: `export OPENROUTER_API_KEY=your_key_here`
  3. Start chatting: `Cara.AI.CLI.start()`

  Usage from iex:

      iex> Cara.AI.CLI.start()
      >> Starting chat session...
      >> Type your message (or 'quit' to exit)
      You: Hello!
      Assistant: Hi there! How can I help you today?
      You: quit
      >> Chat ended.
  """

  alias Cara.AI.Chat
  alias ReqLLM.Context

  @doc """
  Starts an interactive chat session in the IEx console with streaming responses.

  ## Options

    * `:model` - The model to use (default: mistral-7b-instruct)
    * `:system_prompt` - Custom system prompt (default: built-in)
    * `:stream` - Whether to stream responses (default: true)

  ## Examples

      iex> Cara.AI.CLI.start()
      iex> Cara.AI.CLI.start(model: "openrouter:gpt-4")
      iex> Cara.AI.CLI.start(stream: false)
  """
  @spec start(keyword()) :: :ok | {:error, :missing_api_key}
  def start(opts \\ []) do
    with :ok <- validate_api_key() do
      config = build_config(opts)
      print_header(config)
      initial_context = Chat.new_context(config.system_prompt)
      chat_loop(initial_context, config)
    end
  end

  ## Private Functions

  defp build_config(opts) do
    %{
      model: Keyword.get(opts, :model, Chat.default_model()),
      system_prompt:
        Keyword.get(opts, :system_prompt, """
        You are a helpful, friendly AI assistant. Engage in natural conversation,
        answer questions clearly, and be concise unless asked for detailed explanations.
        """),
      stream: Keyword.get(opts, :stream, true)
    }
  end

  @spec validate_api_key() :: :ok | {:error, :missing_api_key}
  defp validate_api_key do
    if System.get_env("OPENROUTER_API_KEY") do
      :ok
    else
      print_api_key_error()
      {:error, :missing_api_key}
    end
  end

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
    # Use the public send_message_stream function
    {:ok, stream, context_builder} = Chat.send_message_stream(message, context, model: config.model)

    IO.write("Assistant: ")
    final_text = consume_and_display_stream(stream, config.stream)
    IO.write("\n\n")

    new_context = context_builder.(final_text)
    chat_loop(new_context, config)
  end

  @spec consume_and_display_stream(Enumerable.t(), boolean()) :: String.t()
  defp consume_and_display_stream(stream, should_stream?) do
    final_text =
      Enum.reduce(stream, "", fn chunk, acc ->
        if should_stream?, do: IO.write(chunk)
        acc <> chunk
      end)

    if !should_stream?, do: IO.write(final_text)
    final_text
  end

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

  defp print_header(config) do
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
