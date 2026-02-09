defmodule Cara.AI.ToolHandlerTest do
  use ExUnit.Case, async: true

  alias Cara.AI.ToolHandler
  alias Cara.AI.Tools.Calculator
  alias ReqLLM.Context

  # Mock chat module for testing
  defmodule MockChat do
    def execute_tool(_tool, %{"expression" => "2+2"}), do: {:ok, 4}
    def execute_tool(_tool, %{"expression" => "10+5"}), do: {:ok, 15}
    def execute_tool(_tool, %{"expression" => "15*2"}), do: {:ok, 30}
    def execute_tool(_tool, %{"expression" => "invalid"}), do: {:error, "Invalid expression"}
    def execute_tool(_tool, %{"expression" => "error"}), do: {:error, %{message: "Syntax error"}}
  end

  describe "handle_tool_calls/4" do
    test "processes single successful tool call" do
      # Arguments must be JSON-encoded strings
      tool_call = ReqLLM.ToolCall.new("call_123", "calculator", Jason.encode!(%{"expression" => "2+2"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call], context, tools, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      assert tool_result.tool_call_id == "call_123"
      # Result should be "4" as a string
      assert hd(tool_result.content).text == "4"
    end

    test "processes multiple tool calls in sequence" do
      tool_call_1 = ReqLLM.ToolCall.new("call_001", "calculator", Jason.encode!(%{"expression" => "10+5"}))
      tool_call_2 = ReqLLM.ToolCall.new("call_002", "calculator", Jason.encode!(%{"expression" => "15*2"}))
      
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call_1, tool_call_2], context, tools, MockChat)

      assert length(result.messages) == 2
      
      [first_result, second_result] = result.messages
      
      assert first_result.role == :tool
      assert first_result.tool_call_id == "call_001"
      assert hd(first_result.content).text == "15"
      
      assert second_result.role == :tool
      assert second_result.tool_call_id == "call_002"
      assert hd(second_result.content).text == "30"
    end

    test "handles empty tool calls list" do
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([], context, tools, MockChat)

      # Context should be unchanged
      assert result == context
      assert length(result.messages) == 0
    end

    test "preserves existing messages in context" do
      # Start with a context that already has messages
      context = 
        Context.new([])
        |> Context.append(Context.user("Hello"))
        |> Context.append(Context.assistant("Hi there!"))

      tool_call = ReqLLM.ToolCall.new("call_123", "calculator", Jason.encode!(%{"expression" => "2+2"}))
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call], context, tools, MockChat)

      # Should have 3 messages: user, assistant, tool
      assert length(result.messages) == 3
      assert Enum.at(result.messages, 0).role == :user
      assert Enum.at(result.messages, 1).role == :assistant
      assert Enum.at(result.messages, 2).role == :tool
    end
  end

  describe "process_tool_call/4" do
    test "successfully executes tool and adds result" do
      tool_call = ReqLLM.ToolCall.new("call_456", "calculator", Jason.encode!(%{"expression" => "10+5"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.process_tool_call(tool_call, tools, context, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      assert tool_result.tool_call_id == "call_456"
      assert hd(tool_result.content).text == "15"
    end

    test "handles tool not found" do
      tool_call = ReqLLM.ToolCall.new("call_789", "nonexistent_tool", Jason.encode!(%{}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.process_tool_call(tool_call, tools, context, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      assert tool_result.tool_call_id == "call_789"
      error_text = hd(tool_result.content).text
      assert error_text =~ "Error: Tool nonexistent_tool not found"
    end

    test "handles tool execution error with string" do
      tool_call = ReqLLM.ToolCall.new("call_error", "calculator", Jason.encode!(%{"expression" => "invalid"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.process_tool_call(tool_call, tools, context, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      assert tool_result.tool_call_id == "call_error"
      error_text = hd(tool_result.content).text
      assert error_text =~ "Error executing tool calculator"
      assert error_text =~ "Invalid expression"
    end

    test "handles tool execution error with map" do
      tool_call = ReqLLM.ToolCall.new("call_error2", "calculator", Jason.encode!(%{"expression" => "error"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.process_tool_call(tool_call, tools, context, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      error_text = hd(tool_result.content).text
      assert error_text =~ "Error executing tool calculator"
      assert error_text =~ "Syntax error"
    end

    test "handles tool with empty tools list" do
      tool_call = ReqLLM.ToolCall.new("call_none", "calculator", Jason.encode!(%{"expression" => "2+2"}))
      context = Context.new([])
      tools = []  # No tools available

      result = ToolHandler.process_tool_call(tool_call, tools, context, MockChat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      error_text = hd(tool_result.content).text
      assert error_text =~ "Error: Tool calculator not found"
    end
  end

  describe "integration with real calculator tool" do
    test "works with actual Calculator tool and Cara.AI.Chat" do
      # This tests the real integration, not just mocks
      tool_call = ReqLLM.ToolCall.new("real_call", "calculator", Jason.encode!(%{"expression" => "(2+3)*4"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call], context, tools, Cara.AI.Chat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      assert tool_result.role == :tool
      # (2+3)*4 = 20
      assert hd(tool_result.content).text == "20"
    end

    test "handles invalid expression with real calculator" do
      tool_call = ReqLLM.ToolCall.new("invalid_call", "calculator", Jason.encode!(%{"expression" => "not_valid"}))
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call], context, tools, Cara.AI.Chat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      error_text = hd(tool_result.content).text
      # Should contain error message
      assert error_text =~ "Error executing tool calculator"
    end
  end

  describe "edge cases" do
    test "handles tool calls with complex arguments" do
      tool_call = ReqLLM.ToolCall.new(
        "complex_call",
        "calculator", 
        Jason.encode!(%{"expression" => "((10 + 5) * 2) - 8"})
      )
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call], context, tools, Cara.AI.Chat)

      assert length(result.messages) == 1
      [tool_result] = result.messages
      # ((10 + 5) * 2) - 8 = 22
      assert hd(tool_result.content).text == "22"
    end

    test "handles multiple errors in sequence" do
      tool_call_1 = ReqLLM.ToolCall.new("err1", "nonexistent", Jason.encode!(%{}))
      tool_call_2 = ReqLLM.ToolCall.new("err2", "calculator", Jason.encode!(%{"expression" => "invalid"}))
      
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls([tool_call_1, tool_call_2], context, tools, MockChat)

      assert length(result.messages) == 2
      
      # Both should be error messages
      Enum.each(result.messages, fn msg ->
        assert msg.role == :tool
        error_text = hd(msg.content).text
        assert error_text =~ "Error"
      end)
    end

    test "handles mix of success and failure" do
      tool_call_1 = ReqLLM.ToolCall.new("success", "calculator", Jason.encode!(%{"expression" => "2+2"}))
      tool_call_2 = ReqLLM.ToolCall.new("failure", "calculator", Jason.encode!(%{"expression" => "invalid"}))
      tool_call_3 = ReqLLM.ToolCall.new("success2", "calculator", Jason.encode!(%{"expression" => "10+5"}))
      
      context = Context.new([])
      tools = [Calculator.calculator_tool()]

      result = ToolHandler.handle_tool_calls(
        [tool_call_1, tool_call_2, tool_call_3], 
        context, 
        tools, 
        MockChat
      )

      assert length(result.messages) == 3
      
      # First should succeed
      assert hd(Enum.at(result.messages, 0).content).text == "4"
      
      # Second should fail
      error_text = hd(Enum.at(result.messages, 1).content).text
      assert error_text =~ "Error executing tool"
      
      # Third should succeed
      assert hd(Enum.at(result.messages, 2).content).text == "15"
    end
  end
end
