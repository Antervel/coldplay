defmodule Cara.AI.ToolHandler do
  @moduledoc """
  Handles tool execution and context management.

  This module delegates to `BranchedLLM.ToolHandler`. See that module for full documentation.
  """

  defdelegate handle_tool_calls(tool_calls, context, available_tools, chat_module), to: BranchedLLM.ToolHandler
  defdelegate process_tool_call(tool_call, available_tools, context, chat_module), to: BranchedLLM.ToolHandler
end
