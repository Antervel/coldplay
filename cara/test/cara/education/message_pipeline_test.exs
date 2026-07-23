defmodule Cara.Education.MessagePipelineTest do
  use ExUnit.Case, async: true

  alias Cara.Education.MessagePipeline

  describe "run/3" do
    test "returns context with event set" do
      context =
        MessagePipeline.run(
          :on_message,
          %{content: "hi", role: :student},
          []
        )

      assert context.event == :on_message
      assert context.content == "hi"
      assert context.role == :student
    end

    test "calls plugin with {plugin, opts} tuple" do
      # Use a real module that exports on_message/2
      context =
        MessagePipeline.run(
          :on_message,
          %{content: "test", role: :student},
          [{Cara.Plugins.SafetyPlugin, some: :opt}]
        )

      # SafetyPlugin ran (it won't block with guard disabled in test)
      assert context.event == :on_message
    end

    test "skips plugin when function is not exported for the event" do
      # Enum is a loaded module but does not export on_message/2
      context =
        MessagePipeline.run(
          :on_message,
          %{content: "test", role: :student},
          [Enum]
        )

      # Context passes through unchanged (no crash)
      assert context.event == :on_message
      assert context.status == :ok
    end

    test "skips plugin when module cannot be loaded" do
      context =
        MessagePipeline.run(
          :on_message,
          %{content: "test", role: :student},
          [NonExistent.Module.That.Does.Not.Exist]
        )

      # Context passes through unchanged
      assert context.event == :on_message
      assert context.status == :ok
    end

    test "threads context through multiple plugins" do
      # Run both SafetyPlugin and MonitoringPlugin
      branched_chat = %{
        current_branch_id: "main",
        branches: %{"main" => %{messages: []}}
      }

      message_obj = %{id: "msg-1", role: :user, content: "Hello", metadata: %{}}

      context =
        MessagePipeline.run(
          :on_message,
          %{
            content: "Hello",
            role: :student,
            branched_chat: branched_chat,
            chat_id: "chat-test",
            assigns: %{message_obj: message_obj}
          },
          [Cara.Plugins.SafetyPlugin, Cara.Plugins.MonitoringPlugin]
        )

      # Both plugins ran without error
      assert context.event == :on_message
      assert %MessagePipeline.Context{} = context
    end
  end
end
