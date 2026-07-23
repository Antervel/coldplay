defmodule Cara.AI.ChatClientTest do
  use ExUnit.Case, async: true

  alias Cara.AI.ChatClient

  describe "default_model/0" do
    test "delegates to BranchedLLM.ChatClient.default_model" do
      # credo:disable-for-next-line
      assert ChatClient.default_model() != nil
    end
  end

  describe "send_message_stream/2" do
    test "raises FunctionClauseError with invalid context" do
      assert_raise FunctionClauseError, fn ->
        ChatClient.send_message_stream(%{}, [])
      end
    end
  end

  describe "execute_tool/2" do
    test "executes a tool function" do
      tool = %ReqLLM.Tool{
        name: "test_tool",
        description: "Test tool",
        callback: fn _ -> "done" end
      }

      assert ChatClient.execute_tool(tool, %{}) == "done"
    end
  end

  describe "stream_text/3" do
    test "delegates to BranchedLLM.ChatClient.stream_text" do
      context = ReqLLM.Context.new([ReqLLM.Context.system("test")])
      # credo:disable-for-next-line
      assert ChatClient.stream_text("openai/gpt-oss-20b", context, []) != nil
    end
  end
end
