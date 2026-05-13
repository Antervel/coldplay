defmodule Cara.Education.PipelinePlugin do
  @moduledoc """
  Defines the behavior for message pipeline plugins.
  """
  alias Cara.Education.MessagePipeline.Context

  @callback on_message(Context.t(), keyword()) :: Context.t()
  @callback on_chunk(Context.t(), keyword()) :: Context.t()
  @callback on_error(Context.t(), keyword()) :: Context.t()

  @optional_callbacks on_message: 2, on_chunk: 2, on_error: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Cara.Education.PipelinePlugin
      alias Cara.Education.MessagePipeline.Context

      def on_message(context, _opts), do: context
      def on_chunk(context, _opts), do: context
      def on_error(context, _opts), do: context

      defoverridable on_message: 2, on_chunk: 2, on_error: 2
    end
  end
end
