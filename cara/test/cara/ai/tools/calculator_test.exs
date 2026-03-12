defmodule Cara.AI.Tools.CalculatorTest do
  use ExUnit.Case, async: true
  alias Cara.AI.Tools.Calculator

  describe "calculator_tool/0" do
    test "returns a ReqLLM.Tool struct" do
      tool = Calculator.calculator_tool()
      assert tool.name == "calculator"
      assert tool.description =~ "Evaluate math expressions"
    end

    test "successfully evaluates simple expression with atom key" do
      tool = Calculator.calculator_tool()
      assert {:ok, 4} = tool.callback.(expression: "2+2")
    end

    test "successfully evaluates simple expression with string key" do
      tool = Calculator.calculator_tool()
      assert {:ok, 4} = tool.callback.(%{"expression" => "2+2"})
    end

    test "successfully evaluates simple expression with map atom key" do
      tool = Calculator.calculator_tool()
      assert {:ok, 4} = tool.callback.(%{expression: "2+2"})
    end

    test "successfully evaluates complex expression" do
      tool = Calculator.calculator_tool()
      # Depending on the version of Abacus, it may return 22 or 22.0
      assert {:ok, result} = tool.callback.(expression: "((10 + 5) * 2) - 8")
      assert result == 22
    end

    test "successfully evaluates power expression" do
      tool = Calculator.calculator_tool()
      # 2^3 = 8
      assert {:ok, result} = tool.callback.(expression: "2 ^ 3")
      assert result == 8
    end

    test "handles missing expression parameter" do
      tool = Calculator.calculator_tool()
      assert {:error, "Missing 'expression' parameter"} = tool.callback.([])
      assert {:error, "Missing 'expression' parameter"} = tool.callback.(%{})
      # Test non-list/non-map args
      assert {:error, "Missing 'expression' parameter"} = tool.callback.(nil)
    end

    test "handles non-binary expression parameter" do
      tool = Calculator.calculator_tool()
      assert {:error, "Missing 'expression' parameter"} = tool.callback.(expression: 123)
    end

    test "handles syntax error in expression" do
      tool = Calculator.calculator_tool()
      # If Abacus returns {:error, ...} it's caught by the case
      # If it raises, it's caught by rescue
      {:error, message} = tool.callback.(expression: "2 + * 2")
      assert message =~ "Invalid expression"
    end

    test "handles division by zero" do
      tool = Calculator.calculator_tool()
      {:error, message} = tool.callback.(expression: "1/0")
      assert message =~ "Invalid expression"
    end

    test "handles other types of Abacus errors" do
      tool = Calculator.calculator_tool()
      # Try an expression that might return an error structure from Abacus
      {:error, message} = tool.callback.(expression: "undefined_func(1)")
      assert message =~ "Invalid expression"
    end
  end
end
