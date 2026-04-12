defmodule Cara.AI.LLMErrorFormatter do
  @moduledoc """
  Formats LLM errors into user-friendly messages.

  This module delegates to `BranchedLLM.LLMErrorFormatter`. See that module for full documentation.
  """

  defdelegate format(exception), to: BranchedLLM.LLMErrorFormatter
end
