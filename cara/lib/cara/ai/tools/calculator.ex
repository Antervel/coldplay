defmodule Cara.AI.Tools.Calculator do
  @moduledoc """
  Calculator tool for ReqLLM.
  """
  alias ReqLLM.Tool

  def calculator_tool do
    Tool.new!(
      name: "calculator",
      description: ~s|Safely evaluate a math expression. Example: {"expression":"(2+3)*7"}|,
      parameter_schema: [
        expression: [type: :string, required: true, doc: "Math expression, e.g., \"(2+3)^2 / 5\""]
      ],
      callback: fn args ->
        # Handle both atom keys (internal) and string keys (JSON)
        expr = args[:expression] || args["expression"]

        if is_binary(expr) do
          case Abacus.eval(expr) do
            {:ok, val} -> {:ok, val}
            {:error, r} -> {:error, "Invalid expression: #{Exception.message(r)}"}
          end
        else
          {:error, "Missing 'expression' parameter"}
        end
      end
    )
  end
end
