defmodule Cara.Education.ChatService do
  @moduledoc """
  Domain logic for chat interactions, decoupled from LiveView.
  """
  alias BranchedLLM.BranchedChat
  alias BranchedLLM.Message
  alias Cara.AI.Guard
  alias Cara.Education.Monitoring
  alias ReqLLM.Context

  @doc """
  Processes a new message from the user.

  Returns:
    * `{:enqueue, branched_chat}` - If AI is busy, message was queued.
    * `{:send, branched_chat, user_message_obj}` - If AI is idle, message was added and can be processed.
    * `{:blocked, branched_chat}` - If message was blocked by content classifier.
  """
  def send_message(branched_chat, message, socket) do
    current_branch_id = branched_chat.current_branch_id

    if BranchedChat.busy?(branched_chat, current_branch_id) do
      {:enqueue, BranchedChat.enqueue_message(branched_chat, current_branch_id, message)}
    else
      if Guard.should_classify?(:student) and Guard.unsafe?(message, :student, branched_chat) do
        # Add user message
        branched_chat = BranchedChat.add_user_message(branched_chat, message)
        user_message_obj = List.last(BranchedChat.get_current_messages(branched_chat))

        Monitoring.broadcast_new_message(socket, socket.assigns.chat_id, user_message_obj)

        # Add blocked assistant message
        blocked_text = Guard.blocked_message()
        branched_chat = add_assistant_message(branched_chat, current_branch_id, blocked_text, socket)

        {:blocked, branched_chat}
      else
        branched_chat = BranchedChat.add_user_message(branched_chat, message)
        user_message_obj = List.last(BranchedChat.get_current_messages(branched_chat))

        Monitoring.broadcast_new_message(
          socket,
          socket.assigns.chat_id,
          user_message_obj
        )

        {:send, branched_chat, user_message_obj}
      end
    end
  end

  @doc """
  Changes the active branch and broadcasts the new state.
  """
  def switch_branch(branched_chat, branch_id, socket) do
    new_branched_chat = BranchedChat.switch_branch(branched_chat, branch_id)

    if new_branched_chat.current_branch_id != branched_chat.current_branch_id do
      Monitoring.broadcast_chat_state(
        socket,
        socket.assigns.chat_id,
        socket.assigns.student_info,
        BranchedChat.get_current_messages(new_branched_chat)
      )
    end

    new_branched_chat
  end

  @doc """
  Creates a new branch from a message and broadcasts the state.
  """
  def branch_off(branched_chat, message_id, socket) do
    new_branched_chat = BranchedChat.branch_off(branched_chat, message_id)

    if new_branched_chat.current_branch_id != branched_chat.current_branch_id do
      Monitoring.broadcast_chat_state(
        socket,
        socket.assigns.chat_id,
        socket.assigns.student_info,
        BranchedChat.get_current_messages(new_branched_chat)
      )
    end

    new_branched_chat
  end

  @doc """
  Deletes a message and broadcasts the event.
  """
  def delete_message(branched_chat, message_id, socket) do
    branched_chat = BranchedChat.delete_message(branched_chat, message_id)

    Monitoring.broadcast_message_deleted(
      socket,
      socket.assigns.chat_id,
      message_id
    )

    branched_chat
  end

  @doc """
  Finalizes an AI response and broadcasts it.
  """
  def finish_ai_response(branched_chat, branch_id, llm_context_builder, socket) do
    branched_chat = BranchedChat.finish_ai_response(branched_chat, branch_id, llm_context_builder)

    # Broadcast the completed AI message
    final_message = List.last(branched_chat.branches[branch_id].messages)

    if Guard.should_classify?(:llm) and Guard.unsafe?(final_message.content, :llm, branched_chat) do
      blocked_text = Guard.blocked_message()

      # Replace content in BranchedChat
      branch = branched_chat.branches[branch_id]
      messages = branch.messages
      {last, rest} = List.pop_at(messages, -1)
      updated_message = %{last | content: blocked_text}
      updated_messages = rest ++ [updated_message]

      new_context = rebuild_context_from_messages(updated_messages, branched_chat)

      updated_branch = %{branch | messages: updated_messages, context: new_context}
      branched_chat = %{branched_chat | branches: Map.put(branched_chat.branches, branch_id, updated_branch)}

      Monitoring.broadcast_new_message(
        socket,
        socket.assigns.chat_id,
        updated_message
      )

      branched_chat
    else
      Monitoring.broadcast_new_message(
        socket,
        socket.assigns.chat_id,
        final_message
      )

      branched_chat
    end
  end

  defp add_assistant_message(branched_chat, branch_id, content, socket) do
    branched_chat = BranchedChat.append_chunk(branched_chat, branch_id, content)

    # We need a context builder. We keep the existing context.
    branched_chat =
      BranchedChat.finish_ai_response(branched_chat, branch_id, fn _ ->
        BranchedChat.get_current_context(branched_chat)
      end)

    final_message = List.last(branched_chat.branches[branch_id].messages)
    Monitoring.broadcast_new_message(socket, socket.assigns.chat_id, final_message)

    branched_chat
  end

  @doc """
  Adds an error message and broadcasts it.
  """
  def add_error_message(branched_chat, branch_id, error_message, socket) do
    branched_chat = BranchedChat.add_error_message(branched_chat, branch_id, error_message)
    error_message_obj = List.last(branched_chat.branches[branch_id].messages)

    Monitoring.broadcast_new_message(
      socket,
      socket.assigns.chat_id,
      error_message_obj
    )

    branched_chat
  end

  @doc """
  Cancels the active task in the current branch.
  """
  def cancel_active_task(branched_chat, socket) do
    current_branch_id = branched_chat.current_branch_id
    branch = branched_chat.branches[current_branch_id]

    if pid = branch.active_task do
      Process.exit(pid, :kill)
    end

    current_messages = branch.messages

    {updated_chat_messages, cancelled_msg_obj} =
      if _user_msg = branch.current_user_message do
        case List.last(current_messages) do
          %{sender: :assistant, content: _content} = last ->
            {current_messages, last}

          _ ->
            cancelled_msg = Message.new(:assistant, "*Cancelled*")
            {current_messages ++ [cancelled_msg], cancelled_msg}
        end
      else
        {current_messages, nil}
      end

    if cancelled_msg_obj && cancelled_msg_obj.content == "*Cancelled*" do
      Monitoring.broadcast_new_message(
        socket,
        socket.assigns.chat_id,
        cancelled_msg_obj
      )
    end

    # Rebuild context for the branch after cancellation
    new_context = rebuild_context_from_messages(updated_chat_messages, branched_chat)

    updated_branch = %{
      branch
      | messages: updated_chat_messages,
        context: new_context,
        active_task: nil,
        pending_messages: [],
        tool_status: nil,
        current_user_message: nil
    }

    branches = Map.put(branched_chat.branches, current_branch_id, updated_branch)
    %{branched_chat | branches: branches}
  end

  defp rebuild_context_from_messages(messages, branched_chat) do
    chat_mod = branched_chat.chat_module

    messages
    |> Enum.drop(1)
    |> Enum.reject(&Message.deleted?/1)
    |> Enum.reduce(chat_mod.reset_context(BranchedChat.get_current_context(branched_chat)), fn msg, acc ->
      case msg.role do
        :user -> Context.append(acc, Context.user(msg.content))
        :assistant -> Context.append(acc, Context.assistant(msg.content))
        :system -> acc
      end
    end)
  end
end
