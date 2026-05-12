defmodule Cara.Plugins.MonitoringPluginTest do
  use ExUnit.Case, async: true

  alias Cara.Education.MessagePipeline.Context
  alias Cara.Plugins.MonitoringPlugin

  describe "on_message/2" do
    test "returns context unchanged when message_obj is nil" do
      context = %Context{
        content: "Hello",
        role: :student,
        event: :on_message,
        chat_id: "chat-1",
        assigns: %{},
        metadata: %{}
      }

      result = MonitoringPlugin.on_message(context, [])
      assert result == context
    end

    test "enriches message with metadata from context" do
      message_obj = %{id: "msg-1", role: :user, content: "Hi", metadata: %{}}

      context = %Context{
        content: "Hi",
        role: :student,
        event: :on_message,
        chat_id: "chat-1",
        socket: nil,
        assigns: %{message_obj: message_obj},
        metadata: %{safety_score: 0.2}
      }

      result = MonitoringPlugin.on_message(context, [])
      enriched_msg = result.assigns[:message_obj]
      assert enriched_msg.metadata == %{safety_score: 0.2}
    end

    test "merges pipeline metadata into existing message metadata" do
      message_obj = %{id: "msg-2", role: :assistant, content: "Hey", metadata: %{existing: true}}

      context = %Context{
        content: "Hey",
        role: :llm,
        event: :on_message,
        chat_id: "chat-2",
        socket: nil,
        assigns: %{message_obj: message_obj},
        metadata: %{safety_score: 0.5}
      }

      result = MonitoringPlugin.on_message(context, [])
      enriched_msg = result.assigns[:message_obj]
      assert enriched_msg.metadata == %{existing: true, safety_score: 0.5}
    end
  end

  describe "on_chunk/2" do
    test "returns context unchanged (no-op)" do
      context = %Context{
        content: "chunk",
        role: :llm,
        event: :on_chunk
      }

      result = MonitoringPlugin.on_chunk(context, [])
      assert result == context
    end
  end
end
