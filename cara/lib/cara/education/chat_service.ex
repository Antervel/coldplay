defmodule Cara.Education.ChatService do
  @moduledoc """
  Domain logic for chat interactions, decoupled from LiveView.
  """
  alias BranchedLLM.BranchedChat
  alias BranchedLLM.Message
  alias Cara.AI.Guard
  alias Cara.Education.MessagePipeline
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
    branch_id = branched_chat.current_branch_id

    if BranchedChat.busy?(branched_chat, branch_id) do
      {:enqueue, BranchedChat.enqueue_message(branched_chat, branch_id, message)}
    else
      branched_chat
      |> prepare_user_message(message)
      |> run_pipeline(message, socket)
      |> handle_pipeline_result(branch_id)
    end
  end

  defp prepare_user_message(branched_chat, message) do
    branched_chat = BranchedChat.add_user_message(branched_chat, message)
    user_message = branched_chat |> BranchedChat.get_current_messages() |> List.last()
    {branched_chat, user_message}
  end

  defp run_pipeline({branched_chat, user_message}, message, socket) do
    pipeline_data = %{
      content: message,
      role: :student,
      branched_chat: branched_chat,
      socket: socket,
      chat_id: socket.assigns.chat_id,
      assigns: %{message_obj: user_message}
    }

    context = MessagePipeline.run(:on_message, pipeline_data)
    {branched_chat, context.assigns.message_obj, context.status, socket}
  end

  defp handle_pipeline_result({branched_chat, user_message, :blocked, socket}, branch_id) do
    branched_chat =
      branched_chat
      |> update_message_in_branch(branch_id, user_message)
      |> add_assistant_message(branch_id, Guard.blocked_message(), socket)

    {:blocked, branched_chat}
  end

  defp handle_pipeline_result({branched_chat, user_message, _status, socket}, branch_id) do
    {:send, update_message_in_branch(branched_chat, branch_id, user_message), user_message, socket}
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
  Handles a streaming chunk from the LLM.

  Runs the `:on_chunk` pipeline (which may modify the chunk content),
  then appends the chunk to the branched chat. Returns the updated
  branched_chat and the (possibly modified) chunk, so the LiveView
  can render the accumulated content.

  This is the domain-layer entry point for streaming chunks —
  all pipeline logic lives here, keeping the LiveView focused on
  presentation (rendering Markdown to HTML and pushing to the client).
  """
  def handle_chunk(branched_chat, branch_id, chunk, chat_id) do
    pipeline_data = %{
      content: chunk,
      role: :llm,
      branched_chat: branched_chat,
      chat_id: chat_id
    }

    context = MessagePipeline.run(:on_chunk, pipeline_data)
    chunk = context.content

    branched_chat = BranchedChat.append_chunk(branched_chat, branch_id, chunk)

    {branched_chat, chunk}
  end

  @doc """
  Finalizes an AI response and broadcasts it.
  """
  def finish_ai_response(branched_chat, branch_id, llm_context_builder, socket) do
    branched_chat = BranchedChat.finish_ai_response(branched_chat, branch_id, llm_context_builder)
    final_message = List.last(branched_chat.branches[branch_id].messages)

    # Run pipeline
    pipeline_data = %{
      content: final_message.content,
      role: :llm,
      branched_chat: branched_chat,
      socket: socket,
      chat_id: socket.assigns.chat_id,
      assigns: %{message_obj: final_message}
    }

    context = MessagePipeline.run(:on_message, pipeline_data)
    final_message = context.assigns.message_obj

    if context.status == :blocked do
      blocked_text = Guard.blocked_message()

      # Replace content in BranchedChat and rebuild context
      updated_message = %{final_message | content: blocked_text}
      branched_chat = replace_last_message_and_rebuild_context(branched_chat, branch_id, updated_message)

      Monitoring.broadcast_new_message(
        socket,
        socket.assigns.chat_id,
        updated_message
      )

      branched_chat
    else
      # Update branched_chat with enriched metadata
      update_message_in_branch(branched_chat, branch_id, final_message)
    end
  end

  defp update_message_in_branch(branched_chat, branch_id, updated_message) do
    branch = branched_chat.branches[branch_id]
    messages = branch.messages

    updated_messages =
      Enum.map(messages, fn msg ->
        if msg.id == updated_message.id, do: updated_message, else: msg
      end)

    updated_branch = %{branch | messages: updated_messages}
    %{branched_chat | branches: Map.put(branched_chat.branches, branch_id, updated_branch)}
  end

  defp replace_last_message_and_rebuild_context(branched_chat, branch_id, updated_message) do
    branch = branched_chat.branches[branch_id]
    messages = branch.messages
    {_last, rest} = List.pop_at(messages, -1)
    updated_messages = rest ++ [updated_message]

    new_context = rebuild_context_from_messages(updated_messages, branched_chat)

    updated_branch = %{branch | messages: updated_messages, context: new_context}
    %{branched_chat | branches: Map.put(branched_chat.branches, branch_id, updated_branch)}
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

    pipeline_data = %{
      content: error_message,
      role: :llm,
      branched_chat: branched_chat,
      socket: socket,
      chat_id: socket.assigns.chat_id,
      assigns: %{message_obj: error_message_obj}
    }

    MessagePipeline.run(:on_error, pipeline_data)

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
