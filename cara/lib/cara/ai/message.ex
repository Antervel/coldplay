defmodule Cara.AI.Message do
  @moduledoc """
  A formal, immutable message structure for AI conversations.

  This module delegates to `BranchedLLM.Message`.
  """

  @type t :: BranchedLLM.Message.t()
  @type role :: BranchedLLM.Message.role()

  defdelegate new(role, content, id \\ nil, metadata \\ %{}), to: BranchedLLM.Message
  defdelegate mark_deleted(msg), to: BranchedLLM.Message
  defdelegate deleted?(msg), to: BranchedLLM.Message
  defdelegate from_map(map), to: BranchedLLM.Message
  defdelegate to_map(msg), to: BranchedLLM.Message
end
