defmodule Cara.AI.Tools.Calculator do
  require Logger

  @moduledoc """
  Calculator tool for ReqLLM.
  """
  alias ReqLLM.Tool

  def calculator_tool do
    Tool.new!(
      name: "calculator",
      description:
        "Evaluate math expressions. Use ^ for powers and square root (e.g. 25 ^ 0.5). Example: {\"expression\":\"2+2\"}",
      parameter_schema: [
        expression: [type: :string, required: true, doc: "The math expression"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)

        # Handle both atom keys (internal) and string keys (JSON) safely
        expr =
          case args do
            m when is_map(m) -> Map.get(m, :expression) || Map.get(m, "expression")
            l when is_list(l) -> Keyword.get(l, :expression)
            _ -> nil
          end

        result =
          if is_binary(expr) do
            try do
              case Abacus.eval(expr) do
                {:ok, val} ->
                  {:ok, val}

                {:error, r} ->
                  {:error, "Invalid expression: #{inspect(r)}"}
              end
            rescue
              e ->
                {:error, "Invalid expression: #{Exception.message(e)}"}
            end
          else
            {:error, "Missing 'expression' parameter"}
          end

        end_time = :erlang.monotonic_time(:millisecond)
        Logger.info("Tool 'calculator' execution took #{end_time - start_time}ms")
        result
      end
    )
  end
end
