defmodule Cara.AI.Tools.Calculator do
  @moduledoc """
  Calculator tool for ReqLLM.
  """
  alias ReqLLM.Tool

  def calculator_tool do
    Tool.new!(
      name: "calculator",
      description: "Evaluate math. Example: {\"expression\":\"2+2\"}",
      parameter_schema: [
        expression: [type: :string, required: true, doc: "The math expression"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)
        # Handle both atom keys (internal) and string keys (JSON)
        expr = args[:expression] || args["expression"]

        result =
          if is_binary(expr) do
            case Abacus.eval(expr) do
              {:ok, val} -> {:ok, val}
              {:error, r} -> {:error, "Invalid expression: #{Exception.message(r)}"}
            end
          else
            {:error, "Missing 'expression' parameter"}
          end

        end_time = :erlang.monotonic_time(:millisecond)
        IO.puts("Tool 'calculator' execution took #{end_time - start_time}ms")
        result
      end
    )
  end
end
