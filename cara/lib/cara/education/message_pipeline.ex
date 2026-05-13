defmodule Cara.Education.MessagePipeline do
  @moduledoc """
  Engine for processing messages through a series of plugins.
  """

  defmodule Context do
    @moduledoc """
    The context carried through the message pipeline.
    """

    @type t :: %__MODULE__{
            content: String.t() | nil,
            role: atom() | nil,
            event: atom() | nil,
            branched_chat: any() | nil,
            socket: any() | nil,
            chat_id: any() | nil,
            metadata: map(),
            status: atom(),
            assigns: map()
          }

    defstruct [
      :content,
      :role,
      :event,
      :branched_chat,
      :socket,
      :chat_id,
      metadata: %{},
      status: :ok,
      assigns: %{}
    ]
  end

  @doc """
  Runs the pipeline for a given event and data.
  """
  def run(event, data, plugins \\ default_plugins()) do
    context = struct(Context, Map.put(data, :event, event))

    Enum.reduce(plugins, context, fn
      {plugin, opts}, acc ->
        apply_plugin(plugin, event, acc, opts)

      plugin, acc ->
        apply_plugin(plugin, event, acc, [])
    end)
  end

  defp apply_plugin(plugin, event, context, opts) do
    case Code.ensure_loaded(plugin) do
      {:module, ^plugin} ->
        if function_exported?(plugin, event, 2) do
          apply(plugin, event, [context, opts])
        else
          context
        end

      {:error, _reason} ->
        context
    end
  end

  defp default_plugins do
    Application.get_env(:cara, :message_pipeline, [])
  end
end
