defmodule Cara.AI.LLMErrorFormatter do
  @moduledoc """
  Formats LLM-related exceptions into user-friendly messages.
  """

  @spec format(Exception.t()) :: String.t()
  def format(%{
        __struct__: ReqLLM.Error.API.Request,
        status: 429,
        response_body: response_body
      }) do
    retry_delay = extract_retry_delay(response_body)
    base_message = "The AI is busy. Wait a moment and try again later."

    case retry_delay do
      nil -> base_message
      delay -> base_message <> " Please retry in #{delay}."
    end
  end

  def format(%{__struct__: ReqLLM.Error.API.Request, status: status}) do
    "API error (status #{status}). Please try again."
  end

  def format(exception) do
    "Error: #{Exception.message(exception)}"
  end

  @spec extract_retry_delay(map()) :: String.t() | nil
  defp extract_retry_delay(response_body) do
    details = Map.get(response_body, "details", [])

    case Enum.find(details, &retry_info?/1) do
      %{"retryDelay" => delay} when is_binary(delay) -> delay
      _ -> nil
    end
  end

  @spec retry_info?(map()) :: boolean()
  defp retry_info?(detail) do
    Map.get(detail, "@type") == "type.googleapis.com/google.rpc.RetryInfo"
  end
end
