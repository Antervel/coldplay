defmodule Cara.Plugins.SafetyPlugin do
  @moduledoc """
  A pipeline plugin that handles safety classification using Cara.AI.Guard.
  """

  use Cara.Education.PipelinePlugin

  alias Cara.AI.Guard
  alias Cara.Education.Monitoring

  @impl true
  def on_message(context, _opts) do
    monitoring_enabled = Monitoring.monitoring_enabled?()
    should_classify = Guard.should_classify?(context.role)

    {status, score} =
      if should_classify or monitoring_enabled do
        Guard.get_classification_and_score(context.content, context.role, context.branched_chat)
      else
        {:safe, 0.0}
      end

    new_status = if should_classify and status == :unsafe, do: :blocked, else: context.status

    %{context | status: new_status}
    |> update_metadata(:safety_score, score)
  end

  defp update_metadata(context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value)}
  end
end
