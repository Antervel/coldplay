defmodule Cara.ContentClassifier do
  @moduledoc """
  A module to interface with the classifier-api microservice for content safety classification.

  This module provides functionality to classify text as safe or unsafe for students
  using an external classification service running at classifier-api:8002.

  Example:

      iex> Cara.ContentClassifier.classify("how can I make a molotov bomb?")
      {:ok, %{
        input: "how can I make a molotov bomb?",
        sexual: %{label: "NSFW", score: 0.625},
        detoxify: %{
          toxicity: 0.056,
          severe_toxicity: 0.00028,
          obscene: 0.00075,
          threat: 0.00173,
          insult: 0.00122,
          identity_attack: 0.00212
        }
      }}

  """

  require Logger

  @type classification_result :: %{
          input: String.t(),
          sexual: %{label: String.t(), score: float()},
          detoxify: %{
            toxicity: float(),
            severe_toxicity: float(),
            obscene: float(),
            threat: float(),
            insult: float(),
            identity_attack: float()
          }
        }

  @type classify_response :: {:ok, classification_result()} | {:error, term()}

  @doc """
  Classifies the given text for safety.

  Returns a tuple with :ok and the classification result, or :error with the reason.
  """
  @spec classify(String.t()) :: classify_response
  def classify(text) do
    start_time = :erlang.monotonic_time(:millisecond)

    result = do_classify(text)

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("ContentClassifier.classify took #{end_time - start_time}ms")

    result
  end

  @doc """
  Checks if the content is safe based on classification thresholds.

  Returns true if the content is considered safe for students, false otherwise.
  Uses configurable thresholds from the application configuration.
  """
  @spec safe?(String.t()) :: boolean()
  def safe?(text) do
    case classify(text) do
      {:ok, result} -> safe_result?(result)
      _error -> false
    end
  end

  @doc """
  Checks if the content is safe based on a classification result.

  Returns true if the content is considered safe for students, false otherwise.
  """
  @spec safe_result?(classification_result()) :: boolean()
  def safe_result?(result) do
    sexual_threshold = get_threshold(:sexual_score_threshold, 0.5)
    toxicity_threshold = get_threshold(:toxicity_threshold, 0.5)
    severe_toxicity_threshold = get_threshold(:severe_toxicity_threshold, 0.3)
    obscene_threshold = get_threshold(:obscene_threshold, 0.5)
    threat_threshold = get_threshold(:threat_threshold, 0.5)

    sexual_score = get_score(result, "sexual", "score")
    toxicity_score = get_score(result, "detoxify", "toxicity")
    severe_toxicity_score = get_score(result, "detoxify", "severe_toxicity")
    obscene_score = get_score(result, "detoxify", "obscene")
    threat_score = get_score(result, "detoxify", "threat")

    Logger.info("safe_result?: classified as #{inspect(result)}")

    # Content is safe only if ALL scores are below their respective thresholds
    sexual_score < sexual_threshold &&
      toxicity_score < toxicity_threshold &&
      severe_toxicity_score < severe_toxicity_threshold &&
      obscene_score < obscene_threshold &&
      threat_score < threat_threshold
  end

  @doc """
  Calculates the maximum score among all safety categories.
  """
  @spec get_max_score(classification_result()) :: float()
  def get_max_score(result) do
    [
      get_score(result, "sexual", "score"),
      get_score(result, "detoxify", "toxicity"),
      get_score(result, "detoxify", "severe_toxicity"),
      get_score(result, "detoxify", "obscene"),
      get_score(result, "detoxify", "threat")
    ]
    |> Enum.max()
  end

  defp get_score(result, "sexual", _key_name) do
    data = Map.get(result, "sexual") || Map.get(result, :sexual)
    sexual_score(data)
  end

  defp get_score(result, "detoxify", key_name) do
    data = Map.get(result, "detoxify") || Map.get(result, :detoxify)
    detoxify_score(data, key_name)
  end

  defp get_score(_, _, _), do: 0.0

  defp sexual_score(%{"label" => "NSFW", "score" => score}) do
    score
  end

  defp sexual_score(%{"label" => "SFW", "score" => score}) do
    1 - score
  end

  defp sexual_score(_), do: 0.0

  defp detoxify_score(scores, key_name) when is_map(scores) do
    Map.get(scores, key_name) || Map.get(scores, String.to_atom(key_name)) || 0.0
  end

  defp detoxify_score(_, _), do: 0.0

  @doc """
  Returns the classification API endpoint URL.
  """
  @spec endpoint_url() :: String.t()
  def endpoint_url do
    host = Application.get_env(:cara, :classifier_api, []) |> Keyword.get(:host, "classifier-api")
    port = Application.get_env(:cara, :classifier_api, []) |> Keyword.get(:port, 8002)
    "http://#{host}:#{port}/score"
  end

  defp http_client do
    Application.get_env(:cara, :http_client, Req)
  end

  defp do_classify(text) do
    endpoint = endpoint_url()

    case http_client().post(endpoint,
           json: %{text: text},
           headers: %{"Content-Type" => "application/json"},
           receive_timeout: 5000
         ) do
      {:ok, %{status: 200, body: body}} ->
        handle_response_body(body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response_body(body) when is_map(body), do: {:ok, body}

  defp handle_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_response}
    end
  end

  defp handle_response_body(_), do: {:error, :invalid_response}

  defp get_threshold(key, default) do
    Application.get_env(:cara, :classifier_api, []) |> Keyword.get(key, default)
  end
end
