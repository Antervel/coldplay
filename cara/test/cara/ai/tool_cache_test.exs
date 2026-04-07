defmodule Cara.AI.ToolCacheTest do
  use Cara.DataCase, async: true

  alias Cara.AI.Chat
  alias Cara.AI.ToolCache
  alias Cara.AI.Tools.Calculator

  describe "ToolCache.get_result/2 and save_result/3" do
    test "returns :error when no result is cached" do
      assert :error == ToolCache.get_result("calculator", %{"expression" => "2+2"})
    end

    test "saves and retrieves a result" do
      tool_name = "calculator"
      args = %{"expression" => "2+2"}
      result = "4"

      {:ok, _} = ToolCache.save_result(tool_name, args, result)

      assert {:ok, ^result} = ToolCache.get_result(tool_name, args)
    end

    test "normalizes arguments for consistent lookup" do
      tool_name = "calculator"
      # Atom keys
      args_atoms = %{expression: "2+2"}
      # String keys
      args_strings = %{"expression" => "2+2"}
      result = "4"

      {:ok, _} = ToolCache.save_result(tool_name, args_atoms, result)

      # Should be able to retrieve with string keys even if saved with atom keys
      assert {:ok, ^result} = ToolCache.get_result(tool_name, args_strings)
    end

    test "returns different results for different arguments" do
      tool_name = "calculator"
      {:ok, _} = ToolCache.save_result(tool_name, %{"expression" => "2+2"}, "4")
      {:ok, _} = ToolCache.save_result(tool_name, %{"expression" => "3+3"}, "6")

      assert {:ok, "4"} = ToolCache.get_result(tool_name, %{"expression" => "2+2"})
      assert {:ok, "6"} = ToolCache.get_result(tool_name, %{"expression" => "3+3"})
    end

    test "returns most recent result" do
      tool_name = "calculator"
      args = %{"expression" => "2+2"}

      {:ok, _} = ToolCache.save_result(tool_name, args, "old result")
      # Wait a tiny bit to ensure different timestamp if needed, but inserted_at usually fine
      Process.sleep(10)
      {:ok, _} = ToolCache.save_result(tool_name, args, "new result")

      assert {:ok, "new result"} = ToolCache.get_result(tool_name, args)
    end

    test "handles list arguments" do
      tool_name = "test_tool"
      args = ["arg1", "arg2"]
      result = "list_result"

      {:ok, _} = ToolCache.save_result(tool_name, args, result)
      assert {:ok, ^result} = ToolCache.get_result(tool_name, args)
    end

    test "handles scalar arguments" do
      tool_name = "scalar_tool"
      args = 123
      result = "scalar_result"

      {:ok, _} = ToolCache.save_result(tool_name, args, result)
      assert {:ok, ^result} = ToolCache.get_result(tool_name, args)
    end

    test "returns error on save failure (validation)" do
      # tool_name is required in ToolResult.changeset
      assert {:error, %Ecto.Changeset{}} = ToolCache.save_result(nil, %{}, "result")
    end
  end

  describe "Chat.execute_tool/2 with caching" do
    test "caches successful tool execution" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "10+10"}

      # First execution: not cached
      assert :error == ToolCache.get_result("calculator", args)
      assert {:ok, 20} = Chat.execute_tool(calculator_tool, args)

      # Second execution: should be cached
      # Note: result is stored as string in cache
      assert {:ok, "20"} = ToolCache.get_result("calculator", args)

      # Calling execute_tool again should return cached result
      # Note that execute_tool returns the cached string if found
      assert {:ok, "20"} = Chat.execute_tool(calculator_tool, args)
    end

    test "does not cache failed tool execution" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "invalid"}

      # Execution fails
      assert {:error, _} = Chat.execute_tool(calculator_tool, args)

      # Nothing should be in cache
      assert :error == ToolCache.get_result("calculator", args)
    end
  end

  describe "Chat.execute_tool/2 telemetry" do
    setup do
      test_pid = self()
      handler_id = "telemetry-test-handler-#{:erlang.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:cara, :ai, :tool, :cache, :hit],
          [:cara, :ai, :tool, :cache, :miss]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits miss telemetry on first call" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "5+5"}

      {:ok, 10} = Chat.execute_tool(calculator_tool, args)

      assert_receive {:telemetry_event, [:cara, :ai, :tool, :cache, :miss], %{count: 1}, %{tool: "calculator"}}
    end

    test "emits hit telemetry on cached call" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "7+7"}

      # First call - miss
      {:ok, 14} = Chat.execute_tool(calculator_tool, args)
      assert_receive {:telemetry_event, [:cara, :ai, :tool, :cache, :miss], _, _}

      # Second call - hit
      {:ok, "14"} = Chat.execute_tool(calculator_tool, args)
      assert_receive {:telemetry_event, [:cara, :ai, :tool, :cache, :hit], %{count: 1}, %{tool: "calculator"}}
    end
  end
end
