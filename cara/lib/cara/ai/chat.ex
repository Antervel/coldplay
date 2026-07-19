defmodule Cara.AI.Chat do
  @moduledoc """
  Core chat functionality for interacting with LLM APIs.

  This is a thin wrapper around `BranchedLLM.Chat` that provides
  Cara-specific configuration defaults.
  """
  import ReqLLM.Context

  require Logger
  require OpenTelemetry.Tracer
  alias OpenTelemetry.Tracer

  alias Cara.AI.ToolCache
  alias Req
  alias ReqLLM.Context
  alias ReqLLM.StreamChunk
  alias ReqLLM.StreamResponse
  alias ReqLLM.StreamResponse.MetadataHandle

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
        final_text =
          stream_response.stream
          |> Enum.reduce("", fn
            %StreamChunk{type: :content, text: text}, acc -> acc <> text
            _, acc -> acc
          end)

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
  @impl true
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
      model: resolve_model(Keyword.get(opts, :model, default_model())),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  defp resolve_model(model) when is_binary(model) do
    case String.split(model, ":", parts: 2) do
      [provider, id] ->
        ReqLLM.model!(%{provider: String.to_atom(provider), id: id})

      _ ->
        model
    end
  end

  defp resolve_model(model), do: model

  @spec add_user_message(Context.t(), String.t()) :: Context.t()
  defp add_user_message(context, message) do
    Context.append(context, user(message))
  end

  @spec add_assistant_message(Context.t(), String.t()) :: Context.t()
  defp add_assistant_message(context, message) do
    Context.append(context, assistant(message))
  end

  @spec call_llm(ReqLLM.model_input(), Context.t(), list()) ::
          {:ok, StreamResponse.t(), list()} | {:error, term()}
  defp call_llm(model, context, tools) do
    model_alias = if is_struct(model), do: "#{model.provider}:#{model.id}", else: model

    Tracer.with_span "llm_call", %{attributes: %{model: model_alias}} do
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
      Logger.info("LLM call_llm(model: #{model_alias}, tools: #{length(tools)}) took #{end_time - start_time}ms")
      result
    end
  end

  defp handle_stream_for_tools(%StreamResponse{} = stream_response) do
    case StreamResponse.classify(stream_response) do
      %{type: :tool_calls, tool_calls: tool_call_maps} ->
        {:ok, dummy_stream_response(stream_response), classify_to_tool_calls(tool_call_maps)}

      %{type: :final_answer, text: text} when is_binary(text) and text != "" ->
        chunk = StreamChunk.text(text)
        {:ok, %{stream_response | stream: [chunk]}, []}

      _ ->
        {:ok, stream_response, []}
    end
  rescue
    e -> {:error, e}
  end

  defp classify_to_tool_calls(tool_call_maps) do
    Enum.map(tool_call_maps, fn %{id: id, name: name, arguments: args} ->
      args_json = if is_map(args), do: Jason.encode!(args), else: args || "{}"
      ReqLLM.ToolCall.new(id, name, args_json)
    end)
  end

  defp dummy_stream_response(%StreamResponse{context: context, model: model}) do
    {:ok, metadata_handle} = MetadataHandle.start_link(fn -> %{} end)

    %StreamResponse{
      stream: [%ReqLLM.StreamChunk{type: :content, text: ""}],
      context: context,
      model: model,
      cancel: fn -> :ok end,
      metadata_handle: metadata_handle
    }
  end

  @doc """
  Executes a given tool with the provided arguments.
  Uses a caching layer to retrieve previous successful results.
  """
  @spec execute_tool(ReqLLM.Tool.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(tool, args) do
    Tracer.with_span "tool_execution", %{attributes: %{tool: tool.name}} do
      case ToolCache.get_result(tool.name, args) do
        {:ok, result} ->
          Logger.info("Tool '#{tool.name}' result retrieved from cache.")
          Tracer.set_attributes(%{"db.cache_hit" => true})
          :telemetry.execute([:cara, :ai, :tool, :cache, :hit], %{count: 1}, %{tool: tool.name})
          {:ok, result}

        :error ->
          Tracer.set_attributes(%{"db.cache_hit" => false})
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
  def health_check(_opts \\ []) do
    %{health_endpoint: health_endpoint} = endpoints()

    Logger.info("Checking AI health at: #{health_endpoint}")

    case Cara.HTTPClient.get(health_endpoint, connect_options: [timeout: 1000], retry: false) do
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
      Application.get_env(:branched_llm, :base_url) ||
        :req_llm
        |> Application.get_env(:openai, [])
        |> Keyword.get(:base_url)

    if String.ends_with?(config_url, "/v1") do
      model_endpoint = config_url
      uri = URI.parse(config_url)
      port_str = if uri.port, do: ":#{uri.port}", else: ""
      base_url = "#{uri.scheme}://#{uri.host}#{port_str}"

      %{
        base_url: base_url,
        model_endpoint: model_endpoint,
        health_endpoint: model_endpoint <> "/models"
      }
    else
      uri = URI.parse(config_url)
      port_str = if uri.port, do: ":#{uri.port}", else: ""
      base_url = "#{uri.scheme}://#{uri.host}#{port_str}"
      model_endpoint = base_url <> "/v1"

      %{
        base_url: base_url,
        model_endpoint: model_endpoint,
        health_endpoint: model_endpoint <> "/models"
      }
    end
  end
end
