defmodule Cara.AI.ChatOrchestrator do
  @moduledoc """
  Orchestrates the LLM request/response lifecycle.

  This module delegates to `BranchedLLM.ChatOrchestrator`. See that module for full documentation.
  """

  defdelegate run(params), to: BranchedLLM.ChatOrchestrator
end
