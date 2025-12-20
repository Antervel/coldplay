defmodule Cara.AI.Chat do
  @moduledoc """
  Interactive chat module using ReqLLM with OpenRouter.

  Usage from iex:

      iex> Cara.AI.Chat.start()
      >> Starting chat session...
      >> Type your message (or 'quit' to exit)
      You: Hello!
      Assistant: Hi there! How can I help you today?
      You: quit
      >> Chat ended.
  """

  import ReqLLM.Context
  alias ReqLLM.Context

  @default_model "openrouter:google/gemma-2-9b-it:free"
  @fallback_models ["google/gemma-3-27b-it:free", "qwen/qwen3-235b-a22b:free"]

  @system_prompt """
  You are a helpful, friendly AI assistant. Engage in natural conversation,
  answer questions clearly, and be concise unless asked for detailed explanations.
  """

  @doc """
  Starts an interactive chat session in the IEx console.

  Options:
    * `:model` - The model to use (default: #{@default_model})
    * `:system_prompt` - Custom system prompt (default: built-in)
    * `:fallback_models` - List of fallback models (default: #{inspect(@fallback_models)})
  """
  def start(opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    system_prompt = Keyword.get(opts, :system_prompt, @system_prompt)
    fallback_models = Keyword.get(opts, :fallback_models, @fallback_models)

    IO.puts("\n>> Starting chat session...")
    IO.puts(">> Model: #{model}")
    IO.puts(">> Type your message (or 'quit' to exit)\n")

    # Initialize context with system message
    initial_context = Context.new([system(system_prompt)])

    chat_loop(initial_context, model, fallback_models)
  end

  @doc """
  Sends a single message and returns the response without entering a loop.
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

    # Generate response
    case call_llm(model, updated_context, fallback_models) do
      {:ok, response} ->
        response_text = ReqLLM.Response.text(response)
        # Add assistant response to context
        final_context = Context.append(updated_context, response.message)
        {:ok, response_text, final_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp chat_loop(context, model, fallback_models) do
    # Get user input
    case get_user_input() do
      :quit ->
        IO.puts(">> Chat ended.\n")
        :ok

      {:ok, user_message} ->
        # Add user message to context
        updated_context = Context.append(context, user(user_message))

        # Get AI response
        case call_llm(model, updated_context, fallback_models) do
          {:ok, response} ->
            response_text = ReqLLM.Response.text(response)
            IO.puts("Assistant: #{response_text}\n")

            # Add assistant response to context and continue
            new_context = Context.append(updated_context, response.message)
            chat_loop(new_context, model, fallback_models)

          {:error, reason} ->
            IO.puts(">> Error: #{inspect(reason)}\n")
            # Continue with same context
            chat_loop(context, model, fallback_models)
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

  defp call_llm(model, context, fallback_models) do
    ReqLLM.generate_text(model, context, provider_options: [openrouter_models: fallback_models])
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
