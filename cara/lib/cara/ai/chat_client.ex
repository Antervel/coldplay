defmodule Cara.AI.ChatClient do
  @moduledoc false
  @behaviour BranchedLLM.ChatClientBehaviour

  @impl true
  def send_message_stream(context, opts) do
    BranchedLLM.ChatClient.send_message_stream(context, opts)
  end

  @impl true
  def execute_tool(tool, args) do
    BranchedLLM.ChatClient.execute_tool(tool, args, [])
  end

  @impl true
  def default_model do
    BranchedLLM.ChatClient.default_model()
  end

  @impl true
  def stream_text(model, context, opts) do
    BranchedLLM.ChatClient.stream_text(model, context, opts)
  end
end
