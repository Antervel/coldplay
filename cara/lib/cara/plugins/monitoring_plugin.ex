defmodule Cara.Plugins.MonitoringPlugin do
  @moduledoc """
  A pipeline plugin that broadcasts messages to the teacher monitoring dashboard.
  """
  use Cara.Education.PipelinePlugin
  alias Cara.Education.Monitoring

  @impl true
  def on_message(context, _opts) do
    case context.assigns[:message_obj] do
      nil ->
        context

      message ->
        # Enrich message with metadata from context (e.g. safety_score)
        message = %{message | metadata: Map.merge(message.metadata, context.metadata)}

        if context.socket && context.chat_id do
          Monitoring.broadcast_new_message(context.socket, context.chat_id, message)
        end

        # Update message_obj in assigns so subsequent plugins see the enriched version
        %{context | assigns: Map.put(context.assigns, :message_obj, message)}
    end
  end

  @impl true
  def on_chunk(context, opts) do
    # Chunks are currently not broadcast to teachers.
    # If they were, we would do it here.
    super(context, opts)
  end
end
