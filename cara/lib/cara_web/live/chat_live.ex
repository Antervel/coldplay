defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  require Logger

  @build_date DateTime.utc_now() |> Calendar.strftime("%Y%m%d")

  alias BranchedLLM.BranchedChat
  alias BranchedLLM.ChatOrchestrator
  alias BranchedLLM.Message
  alias Cara.Education.ChatService
  alias Cara.Education.Monitoring
  alias Cara.Education.Session
  alias CaraWeb.ChatLive.ViewModel
  alias CaraWeb.MarkdownHelpers
  alias ReqLLM.Context

  import CaraWeb.ChatComponents

  @type chat_message :: Message.t()
  defp extract_html({:safe, html}), do: html
  defp extract_html(_), do: ""

  # Get the chat module from config at runtime (allows switching to mock in tests)
  defp chat_module do
    Application.get_env(:cara, :chat_module, Cara.AI.Chat)
  end

  @impl true
  def mount(_params, session, socket) do
    if chat_module().health_check([]) != :ok do
      {:ok, redirect(socket, to: "/sleeping")}
    else
      do_mount(session, socket)
    end
  end

  defp do_mount(session, socket) do
    case Map.get(session, "student_info") do
      %{name: _name, subject: _subject, age: _age, chat_id: _chat_id} = info ->
        {:ok,
         socket
         |> Session.assign_new_session(info, chat_module())
         |> then(fn socket ->
           messages = BranchedChat.get_current_messages(socket.assigns.branched_chat)

           stream(socket, :messages, messages)
         end)
         |> assign_vm()
         |> assign(:app_version, app_version())}

      _incomplete ->
        {:ok, redirect(socket, to: "/student")}
    end
  end

  defp assign_branched_chat(socket, branched_chat) do
    messages = BranchedChat.get_current_messages(branched_chat)

    socket
    |> assign(branched_chat: branched_chat)
    |> stream(:messages, messages, reset: true)
    |> assign_vm()
  end

  defp assign_vm(socket) do
    assign(socket, vm: ViewModel.build(socket.assigns))
  end

  @impl true
  def terminate(_reason, socket) do
    Session.broadcast_left(socket, socket.assigns.chat_id)
    :ok
  end

  @impl true
  def handle_event("toggle", %{"what" => what}, socket) do
    socket =
      case what do
        "sidebar" ->
          assign(socket, show_sidebar: !socket.assigns.show_sidebar)

        "branches" ->
          new_show = !socket.assigns.show_branches
          assign(socket, show_branches: new_show, show_notes: if(new_show, do: false, else: socket.assigns.show_notes))

        "notes" ->
          new_show = !socket.assigns.show_notes

          assign(socket,
            show_notes: new_show,
            show_branches: if(new_show, do: false, else: socket.assigns.show_branches)
          )
      end

    {:noreply, assign_vm(socket)}
  end

  # Fallbacks for tests and legacy hooks
  def handle_event("toggle_sidebar", _params, socket), do: handle_event("toggle", %{"what" => "sidebar"}, socket)
  def handle_event("toggle_branches", _params, socket), do: handle_event("toggle", %{"what" => "branches"}, socket)
  def handle_event("toggle_notes", _params, socket), do: handle_event("toggle", %{"what" => "notes"}, socket)

  @impl true
  def handle_event("switch_branch", %{"id" => id}, socket) do
    branched_chat = ChatService.switch_branch(socket.assigns.branched_chat, id, socket)

    {:noreply,
     socket
     |> assign_branched_chat(branched_chat)
     |> push_event("rendered", %{})}
  end

  @impl true
  def handle_event("branch_off", %{"id" => id}, socket) do
    old_branch_id = socket.assigns.branched_chat.current_branch_id
    branched_chat = ChatService.branch_off(socket.assigns.branched_chat, id, socket)

    if branched_chat.current_branch_id != old_branch_id do
      # Opening branches, so close notes
      {:noreply,
       socket
       |> assign(show_branches: true, show_notes: false)
       |> assign_branched_chat(branched_chat)
       |> push_event("rendered", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_notes", %{"value" => notes}, socket) do
    {:noreply, assign(socket, notes: notes)}
  end

  @impl true
  def handle_event("submit_message", %{"chat" => %{"message" => message}}, socket) do
    do_send_message(message, socket)
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    do_send_message(message, socket)
  end

  @impl true
  def handle_event("validate", %{"chat" => params}, socket) do
    # Update local state so it can be passed to FooterComponent if needed,
    # but FooterComponent also has its own state.
    # For tests, we update socket.assigns.message_data.
    {:noreply, assign(socket, message_data: Map.merge(socket.assigns.message_data, params))}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    branched_chat = ChatService.delete_message(socket.assigns.branched_chat, id, socket)

    {:noreply, assign_branched_chat(socket, branched_chat)}
  end

  # Fallback for old clients (should not happen if refreshed, but for safety)
  def handle_event("delete_message", %{"idx" => idx}, socket) do
    idx = if is_binary(idx), do: String.to_integer(idx), else: idx
    msg_to_delete = Enum.at(BranchedChat.get_current_messages(socket.assigns.branched_chat), idx)

    if msg_to_delete do
      handle_event("delete_message", %{"id" => msg_to_delete.id}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    branched_chat = ChatService.cancel_active_task(socket.assigns.branched_chat, socket)
    {:noreply, assign_branched_chat(socket, branched_chat)}
  end

  @impl true
  def handle_info({:submit_message, message}, socket) do
    do_send_message(message, socket)
  end

  @impl true
  def handle_info({:teacher_joined, _}, socket) do
    Monitoring.broadcast_chat_state(
      socket,
      socket.assigns.chat_id,
      socket.assigns.student_info,
      BranchedChat.get_current_messages(socket.assigns.branched_chat)
    )

    {:noreply, socket}
  end

  # Handle streamed chunks from the LLM
  @impl true
  def handle_info({:llm_chunk, branch_id, chunk}, socket) when is_binary(chunk) do
    {branched_chat, _chunk} =
      ChatService.handle_chunk(
        socket.assigns.branched_chat,
        branch_id,
        chunk,
        socket.assigns.chat_id
      )

    # ALWAYS update the server-side state (no stream reset — push_chunk_to_client uses stream_insert)
    socket = assign(socket, :branched_chat, branched_chat) |> assign_vm()

    # ONLY push events to JS if the branch is currently active
    socket =
      if branch_id == socket.assigns.branched_chat.current_branch_id do
        push_chunk_to_client(socket, branched_chat, branch_id)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle end of LLM stream. Send the `llm_end` event to javascript so Mermaid runs
  @impl true
  def handle_info({:llm_end, branch_id, full_text}, socket) when is_binary(full_text) do
    branched_chat =
      ChatService.finish_ai_response(
        socket.assigns.branched_chat,
        branch_id,
        full_text,
        socket
      )

    socket =
      if branch_id == socket.assigns.branched_chat.current_branch_id do
        push_end_to_client(socket, branched_chat, branch_id)
      else
        assign_branched_chat(socket, branched_chat)
      end
      |> process_next_message_or_idle(branch_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:llm_status, branch_id, status}, socket) do
    branched_chat = BranchedChat.set_tool_status(socket.assigns.branched_chat, branch_id, status)
    {:noreply, assign_branched_chat(socket, branched_chat)}
  end

  @impl true
  def handle_info({:update_tool_usage_counts, tool_usage_counts}, socket) do
    {:noreply, assign(socket, :tool_usage_counts, tool_usage_counts)}
  end

  # Ignore PubSub events intended for the teacher dashboard
  @impl true
  def handle_info({:chat_started, _}, socket), do: {:noreply, socket}
  @impl true
  def handle_info({:chat_state, _}, socket), do: {:noreply, socket}
  @impl true
  def handle_info({:new_message, _}, socket), do: {:noreply, socket}
  @impl true
  def handle_info({:message_deleted, _}, socket), do: {:noreply, socket}
  @impl true
  def handle_info({:chat_left, _}, socket), do: {:noreply, socket}

  # Handle LLM metadata (token usage, etc.)
  @impl true
  def handle_info({:llm_metadata, _branch_id, _metadata}, socket), do: {:noreply, socket}

  # Handle tool call events from the orchestrator
  @impl true
  def handle_info({:llm_tool_called, _branch_id, _info}, socket), do: {:noreply, socket}

  # Handle LLM errors
  @impl true
  def handle_info({:llm_error, branch_id, error_message}, socket) when is_binary(error_message) do
    branched_chat =
      ChatService.add_error_message(
        socket.assigns.branched_chat,
        branch_id,
        error_message,
        socket
      )

    socket
    |> assign_branched_chat(branched_chat)
    |> process_next_message_or_idle(branch_id)
    |> then(&{:noreply, &1})
  end

  ## Private Functions

  defp push_chunk_to_client(socket, branched_chat, branch_id) do
    streaming_message = get_last_assistant_message(branched_chat, branch_id)

    message_content = streaming_message && streaming_message.content

    prefix =
      if streaming_message,
        do: "#{streaming_message.id}-#{branch_id}",
        else: "main"

    rendered_html =
      if message_content do
        MarkdownHelpers.render_markdown(message_content, prefix)
      else
        ""
      end

    socket
    |> push_event("llm_chunk", %{
      message_id: streaming_message && streaming_message.id,
      branch_id: branch_id,
      rendered_html: extract_html(rendered_html)
    })
    |> then(fn socket ->
      if streaming_message do
        stream_insert(socket, :messages, streaming_message)
      else
        socket
      end
    end)
  end

  defp push_end_to_client(socket, branched_chat, branch_id) do
    final_message = get_last_assistant_message(branched_chat, branch_id)

    socket
    |> assign(branched_chat: branched_chat)
    |> assign_vm()
    |> then(fn socket ->
      if final_message do
        stream_insert(socket, :messages, final_message)
      else
        socket
      end
    end)
    |> push_event("llm_end", %{})
  end

  defp process_next_message_or_idle(socket, branch_id) do
    branched_chat = socket.assigns.branched_chat
    {next_message, branched_chat} = BranchedChat.dequeue_message(branched_chat, branch_id)

    if next_message do
      Monitoring.broadcast_new_message(
        socket,
        socket.assigns.chat_id,
        List.last(branched_chat.branches[branch_id].messages)
      )

      socket
      |> assign_branched_chat(branched_chat)
      |> start_llm_stream(branch_id, next_message)
    else
      assign_branched_chat(socket, branched_chat)
    end
  end

  @spec do_send_message(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_send_message(message, socket) do
    if message_blank?(message) do
      {:noreply, socket}
    else
      branched_chat = socket.assigns.branched_chat
      current_branch_id = branched_chat.current_branch_id

      case ChatService.send_message(branched_chat, message, socket) do
        {:enqueue, branched_chat} ->
          {:noreply, assign_branched_chat(socket, branched_chat)}

        {:send, branched_chat, user_message_obj, socket} ->
          socket =
            socket
            |> assign_branched_chat(branched_chat)
            |> start_llm_stream(current_branch_id, user_message_obj.content)

          {:noreply, socket}

        {:blocked, branched_chat} ->
          {:noreply, assign_branched_chat(socket, branched_chat)}
      end
    end
  end

  defp message_blank?(message), do: String.trim(message) == ""

  defp orchestrator_chat_module do
    Application.get_env(:cara, :orchestrator_chat_module, Cara.AI.ChatClient)
  end

  @spec start_llm_stream(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp start_llm_stream(socket, branch_id, message) do
    branched_chat = BranchedChat.set_tool_status(socket.assigns.branched_chat, branch_id, "Thinking...")

    context = branched_chat.branches[branch_id].context
    context_with_msg = Context.append(context, Context.user(message))

    branched_chat = put_in(branched_chat.branches[branch_id].context, context_with_msg)

    caller_pid = self()

    llm_call_params = %{
      llm_context: context_with_msg,
      on_event: fn event -> send(caller_pid, event) end,
      llm_tools: socket.assigns.llm_tools,
      chat_mod: orchestrator_chat_module(),
      tool_usage_counts: socket.assigns.tool_usage_counts,
      branch_id: branch_id
    }

    {:ok, pid} = ChatOrchestrator.run(llm_call_params)

    branched_chat = BranchedChat.set_active_task(branched_chat, branch_id, pid, message)
    assign_branched_chat(socket, branched_chat)
  end

  @spec app_version() :: String.t()
  defp app_version do
    vsn = Application.spec(:cara, :vsn) |> to_string
    "#{vsn} - #{@build_date}"
  end

  # Helper function to get the last assistant message from a branch
  defp get_last_assistant_message(branched_chat, branch_id) do
    case branched_chat.branches[branch_id] do
      %{messages: messages} ->
        messages
        |> Enum.reverse()
        |> Enum.find(&(&1.role == :assistant))

      _ ->
        nil
    end
  end
end
