defmodule Cara.AI.LLM.StreamParser do
  @moduledoc """
  A pure functional module for parsing and processing LLM response streams.

  This module delegates to `BranchedLLM.LLM.StreamParser`. See that module for full documentation.
  """

  defdelegate consume_until_intent(stream), to: BranchedLLM.LLM.StreamParser
  defdelegate extract_tool_calls(chunks), to: BranchedLLM.LLM.StreamParser
  defdelegate consume_to_text(stream), to: BranchedLLM.LLM.StreamParser
  defdelegate accumulate_text(chunk, acc), to: BranchedLLM.LLM.StreamParser
end
