defmodule Cara.AI.ToolsTest do
  use ExUnit.Case, async: true
  alias Cara.AI.Tools

  describe "load_tools/0" do
    test "loads default tools when no config is set" do
      # Ensure config is reset to default
      Application.delete_env(:cara, :enabled_tools)

      tools = Tools.load_tools()
      assert length(tools) == 3
      assert Enum.any?(tools, fn t -> t.name == "calculator" end)
      assert Enum.any?(tools, fn t -> t.name == "wikipedia_search" end)
      assert Enum.any?(tools, fn t -> t.name == "wikipedia_get_article" end)
    end

    test "loads specific tools from config" do
      Application.put_env(:cara, :enabled_tools, [:calculator])
      on_exit(fn -> Application.delete_env(:cara, :enabled_tools) end)

      tools = Tools.load_tools()
      assert length(tools) == 1
      assert hd(tools).name == "calculator"
    end

    test "loads tools by string name" do
      Application.put_env(:cara, :enabled_tools, ["calculator", "wikipedia_search"])
      on_exit(fn -> Application.delete_env(:cara, :enabled_tools) end)

      tools = Tools.load_tools()
      assert length(tools) == 2
      assert Enum.any?(tools, fn t -> t.name == "calculator" end)
      assert Enum.any?(tools, fn t -> t.name == "wikipedia_search" end)
    end
  end
end
