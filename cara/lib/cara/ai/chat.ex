defmodule Cara.AI.Chat do
  @moduledoc """
  Core chat functionality for interacting with LLM APIs.

  This is a thin wrapper around `BranchedLLM.Chat` that provides
  Cara-specific configuration defaults.
  """
  import ReqLLM.Context

  require Logger
  require OpenTelemetry.Tracer

  alias BranchedLLM.LLM.StreamParser
  alias Cara.AI.ToolCache
  alias Req
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  @behaviour BranchedLLM.ChatBehaviour
  @type stream_chunk :: %{type: atom(), text: String.t()}

  ## Public API

  @doc """
  Sends a single message and returns the response without entering a loop.
  Uses streaming internally but returns the complete text.
  """
  @impl BranchedLLM.ChatBehaviour
  @spec send_message(String.t(), Context.t(), keyword()) ::
          {:ok, String.t(), Context.t()} | {:error, term()}
  def send_message(message, context, opts \\ []) do
    config = build_config(opts)
    updated_context = add_user_message(context, message)

    case call_llm(config.model, updated_context, config.tools) do
      {:ok, stream_response, _tool_calls} ->
        final_text = StreamParser.consume_to_text(stream_response.stream)
        final_context = add_assistant_message(updated_context, final_text)
        {:ok, final_text, final_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a message and returns a stream of text chunks plus the updated context,
  and any tool calls made by the LLM.
  """
  @impl BranchedLLM.ChatBehaviour
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
  """
  @impl BranchedLLM.ChatBehaviour
  @spec new_context(String.t()) :: Context.t()
  def new_context(system_prompt) do
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
  @impl BranchedLLM.ChatBehaviour
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
    Application.get_env(:cara, :ai_model, "openai:cara-cpu")
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
    OpenTelemetry.Tracer.with_span "llm_call", %{attributes: %{model: model}} do
      Logger.info("LLM call_llm starting with context: #{inspect(context)}")
      start_time = :erlang.monotonic_time(:millisecond)

      %{model_endpoint: model_endpoint} = endpoints()

      result =
        case ReqLLM.stream_text(model, context.messages, tools: tools, base_url: model_endpoint) do
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
  end

  defp handle_stream_for_tools(%StreamResponse{stream: stream} = stream_response) do
    case StreamParser.consume_until_intent(stream) do
      {:tool_call, consumed_chunks, remaining_stream} ->
        all_chunks = consumed_chunks ++ Enum.to_list(remaining_stream)
        tool_calls = StreamParser.extract_tool_calls(all_chunks)
        {:ok, dummy_stream_response(stream_response), tool_calls}

      {:content, consumed_chunks, remaining_stream} ->
        new_stream = Stream.concat(consumed_chunks, remaining_stream)
        {:ok, %{stream_response | stream: new_stream}, []}

      {:empty, _consumed_chunks} ->
        {:ok, stream_response, []}
    end
  rescue
    e -> {:error, e}
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

  @doc """
  Executes a given tool with the provided arguments.
  Uses a caching layer to retrieve previous successful results.
  """
  @impl BranchedLLM.ChatBehaviour
  @spec execute_tool(ReqLLM.Tool.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(tool, args) do
    OpenTelemetry.Tracer.with_span "tool_execution", %{attributes: %{tool: tool.name}} do
      case ToolCache.get_result(tool.name, args) do
        {:ok, result} ->
          Logger.info("Tool '#{tool.name}' result retrieved from cache.")
          OpenTelemetry.Tracer.set_attributes(%{"db.cache_hit" => true})
          :telemetry.execute([:cara, :ai, :tool, :cache, :hit], %{count: 1}, %{tool: tool.name})
          {:ok, result}

        :error ->
          OpenTelemetry.Tracer.set_attributes(%{"db.cache_hit" => false})
          :telemetry.execute([:cara, :ai, :tool, :cache, :miss], %{count: 1}, %{tool: tool.name})

          case ReqLLM.Tool.execute(tool, args) do
            {:ok, result} = success ->
              ToolCache.save_result(tool.name, args, result)
              success

            error ->
              error
          end
      end
    end
  end

  @doc """
  Checks if the configured LLM provider is available.
  """
  @impl BranchedLLM.ChatBehaviour
  def health_check do
    %{health_endpoint: health_endpoint} = endpoints()

    Logger.info("Checking AI health at: #{health_endpoint}")

    case Req.new(
           connect_options: [timeout: 1000],
           retry: false
         )
         |> OpentelemetryReq.attach(no_path_params: true)
         |> Req.get(url: health_endpoint) do
      {:ok, %{status: 200}} ->
        Logger.info("AI health check successful")
        :ok

      {:ok, %{status: status}} ->
        Logger.info("AI health check failed with status: #{status}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.info("AI health check failed with error: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp endpoints do
    config_url =
      :req_llm
      |> Application.get_env(:openai, [])
      |> Keyword.get(:base_url)

    uri = URI.parse(config_url)
    port_str = if uri.port, do: ":#{uri.port}", else: ""
    base_url = "#{uri.scheme}://#{uri.host}#{port_str}"

    %{
      base_url: base_url,
      model_endpoint: base_url <> "/v1",
      health_endpoint: base_url <> "/api/tags"
    }
  end
end
