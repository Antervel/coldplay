defmodule CaraWeb.ChatLive.ViewModel do
  @moduledoc """
  View model for the ChatLive interface.
  Prepares complex state for rendering in templates.
  """
  alias BranchedLLM.BranchedChat

  def build(assigns) do
    branched_chat = assigns.branched_chat
    current_branch_id = branched_chat.current_branch_id
    current_branch = branched_chat.branches[current_branch_id]

    messages = BranchedChat.get_current_messages(branched_chat)
    last_message = List.last(messages)

    %{
      current_branch: current_branch,
      last_idx: length(messages) - 1,
      last_message_id: if(last_message, do: last_message.id, else: nil),
      message_idx_map: Enum.with_index(messages) |> Map.new(fn {msg, idx} -> {msg.id, idx} end),
      is_main_branch: current_branch_id == "main",
      current_branch_name: if(current_branch.name == "", do: "New branch...", else: current_branch.name),
      show_any_right_panel: assigns.show_branches or assigns.show_notes
    }
  end
end
