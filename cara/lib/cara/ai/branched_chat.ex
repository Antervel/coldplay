defmodule Cara.AI.BranchedChat do
  @moduledoc """
  Manages a tree-like conversation structure with multiple branches.

  This module delegates to `BranchedLLM.BranchedChat`. See that module for full documentation.
  """

  @type t :: BranchedLLM.BranchedChat.t()

  defdelegate new(chat_module, initial_messages, initial_context), to: BranchedLLM.BranchedChat
  defdelegate switch_branch(t, branch_id), to: BranchedLLM.BranchedChat
  defdelegate add_user_message(t, content), to: BranchedLLM.BranchedChat
  defdelegate append_chunk(t, branch_id, chunk), to: BranchedLLM.BranchedChat
  defdelegate finish_ai_response(t, branch_id, llm_context_builder), to: BranchedLLM.BranchedChat
  defdelegate add_error_message(t, branch_id, error_content), to: BranchedLLM.BranchedChat
  defdelegate branch_off(t, message_id), to: BranchedLLM.BranchedChat
  defdelegate delete_message(t, message_id), to: BranchedLLM.BranchedChat
  defdelegate build_tree(t), to: BranchedLLM.BranchedChat
  defdelegate get_current_messages(t), to: BranchedLLM.BranchedChat
  defdelegate get_current_context(t), to: BranchedLLM.BranchedChat
  defdelegate busy?(t, branch_id), to: BranchedLLM.BranchedChat
  defdelegate set_active_task(t, branch_id, pid, user_message), to: BranchedLLM.BranchedChat
  defdelegate clear_active_task(t, branch_id), to: BranchedLLM.BranchedChat
  defdelegate enqueue_message(t, branch_id, message), to: BranchedLLM.BranchedChat
  defdelegate dequeue_message(t, branch_id), to: BranchedLLM.BranchedChat
  defdelegate set_tool_status(t, branch_id, status), to: BranchedLLM.BranchedChat
end
