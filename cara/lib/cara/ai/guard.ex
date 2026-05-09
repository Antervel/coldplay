defmodule Cara.AI.Guard do
  @moduledoc """
  Moderation layer using Llama-Guard 3 via Ollama.
  This module checks messages for safety violations before they are sent to or returned from the main LLM.
  """

  require Logger

  alias ReqLLM.Context

  @type guard_result :: :safe | {:unsafe, String.t()}

  @doc """
  Checks if a message is safe according to the Llama-Guard 3 model.

  ## Options

  * `:context` - The conversation context (optional, used when `send_history: true`)

  ## Examples

      iex> Cara.AI.Guard.check("Hello, how are you?")
      :safe

      iex> Cara.AI.Guard.check("unsafe content")
      {:unsafe, "Sorry, I can't answer about this topic. What else do you want to know about?"}

  """

  @spec check(String.t(), keyword()) :: guard_result()

  def check(message, opts \\ []) when is_binary(message) do
    if enabled?() do
      do_check(message, opts)
    else
      return_safe()
    end
  end

  @doc """
  Returns the configured violation message for a given Llama-Guard code.

  ## Examples

      iex> Cara.AI.Guard.get_violation_message("S12")
      "Sorry, I can't answer about this topic. What else do you want to know about?"

      iex> Cara.AI.Guard.get_violation_message("S1")
      "Violent Crimes"

  """

  @spec get_violation_message(String.t()) :: String.t()

  def get_violation_message(code) when is_binary(code) do
    config =
      case Application.get_env(:cara, :guard, %{}) do
        map when is_map(map) -> map
        list when is_list(list) -> Map.new(list)
        _ -> %{}
      end

    messages = Map.get(config, :violation_messages, %{})
    key = code |> String.downcase() |> String.to_atom()

    Map.get(
      messages,
      key,
      "Sorry, I can't answer about this topic. What else do you want to know about?"
    )
  end

  ## Private Functions

  defp do_check(message, opts) do
    context = Keyword.get(opts, :context, nil)
    model = get_model()
    base_url = get_base_url()
    prompt = build_prompt(message, context)

    body = %{
      model: model,
      messages: [%{role: "user", content: prompt}]
    }

    headers = [{"Content-Type", "application/json"}]

    case Req.post(base_url <> "/chat/completions", json: body, headers: headers, retry: false) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_guard_response(response_body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Guard check failed with status #{status}: #{inspect(body)}")
        return_safe()

      {:error, reason} ->
        Logger.error("Guard check request failed: #{inspect(reason)}")
        return_safe()
    end
  end

  defp build_prompt(message, context) when is_nil(context) or context == %{} do
    message
  end

  defp build_prompt(message, %Context{} = context) do
    if send_history?() do
      history_text =
        context.messages
        |> Enum.filter(fn msg -> msg.role in [:user, :assistant] end)
        |> Enum.map_join("\n", fn msg ->
          text = get_message_text(msg)
          "#{msg.role}: #{text}"
        end)

      if history_text != "" do
        "Conversation history:\n#{history_text}\n\nCurrent message:\n#{message}"
      else
        message
      end
    else
      message
    end
  end

  defp get_message_text(%{content: content}) when is_list(content) do
    content
    |> Enum.filter(fn part -> Map.get(part, :type) == :text end)
    |> Enum.map_join("", fn part -> Map.get(part, :text, "") end)
  end

  defp get_message_text(%{content: content}) when is_binary(content) do
    content
  end

  defp get_message_text(_), do: ""

  defp parse_guard_response(response_body) when is_binary(response_body) do
    case Jason.decode(response_body) do
      {:ok, decoded} -> parse_guard_response(decoded)
      {:error, _} -> return_safe()
    end
  end

  defp parse_guard_response(response_body) when is_map(response_body) do
    choices = Map.get(response_body, "choices", [])

    case choices do
      [] ->
        return_safe()

      [first_choice | _] ->
        message = Map.get(first_choice, "message", %{})
        content = Map.get(message, "content", "") || ""
        parse_guard_content(content)

      _ ->
        return_safe()
    end
  end

  defp parse_guard_response(_), do: return_safe()

  defp parse_guard_content(content) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "safe" ->
        :safe

      String.starts_with?(trimmed, "unsafe") ->
        code =
          trimmed
          |> String.split("\n", trim: true)
          |> List.last()
          |> String.trim()

        {:unsafe, get_violation_message(code)}

      true ->
        return_safe()
    end
  end

  defp parse_guard_content(_), do: return_safe()

  defp get_guard_config do
    case Application.get_env(:cara, :guard, %{}) do
      map when is_map(map) -> map
      list when is_list(list) -> Map.new(list)
      _ -> %{}
    end
  end

  @doc """
  Normalizes a guard config value to a map for downstream use.
  Accepts maps, keyword lists, or any other value (defaults to empty map).
  """

  def normalize_config(map) when is_map(map) and not is_struct(map), do: map

  def normalize_config(list) when is_list(list) do
    Map.new(list)
  end

  def normalize_config(_), do: %{}

  defp enabled? do
    config = get_guard_config()
    Map.get(config, :enabled, false)
  end

  defp send_history? do
    config = get_guard_config()
    Map.get(config, :send_history, false)
  end

  defp get_model do
    config = get_guard_config()
    Map.get(config, :model, "llama-guard3:1b")
  end

  defp get_base_url do
    :req_llm
    |> Application.get_env(:openai, [])
    |> Keyword.get(:base_url)
  end

  defp return_safe do
    :safe
  end
end
