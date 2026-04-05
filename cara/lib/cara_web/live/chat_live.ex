defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  require Logger

  alias Cara.AI.BranchedChat
  alias Cara.AI.ChatOrchestrator
  alias Cara.AI.Prompt
  alias Cara.AI.Tools

  @type chat_message :: %{
          sender: :user | :assistant,
          content: String.t(),
          id: String.t(),
          deleted: boolean()
        }

  # Get the chat module from config at runtime (allows switching to mock in tests)
  defp chat_module do
    Application.get_env(:cara, :chat_module, Cara.AI.Chat)
  end

  defp monitoring_enabled? do
    Application.get_env(:cara, :enable_teacher_monitoring, true)
  end

  defp welcome_message_for_student(%{name: name, subject: subject}) do
    %{
      sender: :assistant,
      content: "Hello **#{name}**! Let's learn about #{subject} together! 🎓",
      id: Ecto.UUID.generate(),
      deleted: false
    }
  end

  @impl true
  def mount(_params, session, socket) do
    if chat_module().health_check() != :ok do
      {:ok, redirect(socket, to: "/sleeping")}
    else
      do_mount(session, socket)
    end
  end

  defp do_mount(session, socket) do
    case Map.get(session, "student_info") do
      %{name: _name, subject: _subject, age: _age, chat_id: chat_id} = info ->
        system_prompt = Prompt.render_greeting_prompt(info)
        llm_tools = Tools.load_tools()

        ui_config = Application.get_env(:cara, :ui, %{})
        bubble_width = Map.get(ui_config, :bubble_width, "40%")

        initial_messages = [welcome_message_for_student(info)]
        initial_context = chat_module().new_context(system_prompt)

        branched_chat = BranchedChat.new(chat_module(), initial_messages, initial_context)

        if connected?(socket) and monitoring_enabled?() do
          Phoenix.PubSub.subscribe(Cara.PubSub, "teacher:monitor")

          Phoenix.PubSub.broadcast(
            Cara.PubSub,
            "teacher:monitor",
            {:chat_started, %{id: chat_id, student: info}}
          )
        end

        {:ok,
         assign(socket,
           branched_chat: branched_chat,
           show_branches: false,
           message_data: %{"message" => ""},
           app_version: app_version(),
           student_info: info,
           llm_tools: llm_tools,
           bubble_width: bubble_width,
           tool_usage_counts:
             Enum.reduce(llm_tools, %{}, fn tool, acc ->
               Map.put(acc, tool.name, 0)
             end),
           show_notes: false,
           notes: ""
         )
         |> assign(:chat_id, chat_id)}

      _incomplete ->
        {:ok, redirect(socket, to: "/student")}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :chat_id) and monitoring_enabled?() do
      Phoenix.PubSub.broadcast(
        Cara.PubSub,
        "teacher:monitor",
        {:chat_left, %{id: socket.assigns.chat_id}}
      )
    end

    :ok
  end

  @impl true
  def handle_event("toggle_branches", _params, socket) do
    new_show_branches = !socket.assigns.show_branches
    # If opening branches, close notes
    new_show_notes = if new_show_branches, do: false, else: socket.assigns.show_notes
    {:noreply, assign(socket, show_branches: new_show_branches, show_notes: new_show_notes)}
  end

  @impl true
  def handle_event("switch_branch", %{"id" => id}, socket) do
    branched_chat = BranchedChat.switch_branch(socket.assigns.branched_chat, id)

    if branched_chat.current_branch_id != socket.assigns.branched_chat.current_branch_id do
      maybe_broadcast_monitoring(
        socket,
        {:chat_state,
         %{
           id: socket.assigns.chat_id,
           student: socket.assigns.student_info,
           messages: BranchedChat.get_current_messages(branched_chat)
         }}
      )
    end

    {:noreply, assign(socket, branched_chat: branched_chat)}
  end

  @impl true
  def handle_event("branch_off", %{"id" => id}, socket) do
    branched_chat = BranchedChat.branch_off(socket.assigns.branched_chat, id)

    if branched_chat.current_branch_id != socket.assigns.branched_chat.current_branch_id do
      maybe_broadcast_monitoring(
        socket,
        {:chat_state,
         %{
           id: socket.assigns.chat_id,
           student: socket.assigns.student_info,
           messages: BranchedChat.get_current_messages(branched_chat)
         }}
      )

      # Opening branches, so close notes
      {:noreply, assign(socket, branched_chat: branched_chat, show_branches: true, show_notes: false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_notes", _params, socket) do
    new_show_notes = !socket.assigns.show_notes
    # If opening notes, close branches
    new_show_branches = if new_show_notes, do: false, else: socket.assigns.show_branches
    {:noreply, assign(socket, show_notes: new_show_notes, show_branches: new_show_branches)}
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
    updated_message_data = Map.merge(socket.assigns.message_data, params)
    {:noreply, assign(socket, message_data: updated_message_data)}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    branched_chat = BranchedChat.delete_message(socket.assigns.branched_chat, id)

    maybe_broadcast_monitoring(
      socket,
      {:message_deleted, %{chat_id: socket.assigns.chat_id, message_id: id}}
    )

    {:noreply, assign(socket, branched_chat: branched_chat)}
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
    branched_chat = socket.assigns.branched_chat
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
            cancelled_msg = %{
              sender: :assistant,
              content: "*Cancelled*",
              id: Ecto.UUID.generate(),
              deleted: false
            }

            {current_messages ++ [cancelled_msg], cancelled_msg}
        end
      else
        {current_messages, nil}
      end

    if cancelled_msg_obj && cancelled_msg_obj.content == "*Cancelled*" do
      maybe_broadcast_monitoring(
        socket,
        {:new_message, %{chat_id: socket.assigns.chat_id, message: cancelled_msg_obj}}
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
    branched_chat = %{branched_chat | branches: branches}

    {:noreply, assign(socket, branched_chat: branched_chat)}
  end

  @impl true
  def handle_info({:teacher_joined, _}, socket) do
    maybe_broadcast_monitoring(
      socket,
      {:chat_state,
       %{
         id: socket.assigns.chat_id,
         student: socket.assigns.student_info,
         messages: BranchedChat.get_current_messages(socket.assigns.branched_chat)
       }}
    )

    {:noreply, socket}
  end

  # Handle streamed chunks from the LLM
  @impl true
  def handle_info({:llm_chunk, branch_id, chunk}, socket) when is_binary(chunk) do
    branched_chat = BranchedChat.append_chunk(socket.assigns.branched_chat, branch_id, chunk)
    {:noreply, assign(socket, branched_chat: branched_chat)}
  end

  # Handle end of LLM stream. Send the `llm_end` event to javascript so Mermaid runs
  @impl true
  def handle_info({:llm_end, branch_id, llm_context_builder}, socket)
      when is_function(llm_context_builder, 1) do
    branched_chat =
      BranchedChat.finish_ai_response(socket.assigns.branched_chat, branch_id, llm_context_builder)

    # Broadcast the completed AI message
    final_message = List.last(branched_chat.branches[branch_id].messages)

    maybe_broadcast_monitoring(
      socket,
      {:new_message, %{chat_id: socket.assigns.chat_id, message: final_message}}
    )

    socket =
      socket
      |> assign(branched_chat: branched_chat)
      |> push_event("llm_end", %{})
      |> process_next_message_or_idle(branch_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:llm_status, branch_id, status}, socket) do
    branched_chat = BranchedChat.set_tool_status(socket.assigns.branched_chat, branch_id, status)
    {:noreply, assign(socket, branched_chat: branched_chat)}
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

  # Handle LLM errors
  @impl true
  def handle_info({:llm_error, branch_id, error_message}, socket) when is_binary(error_message) do
    branched_chat = BranchedChat.add_error_message(socket.assigns.branched_chat, branch_id, error_message)
    error_message_obj = List.last(branched_chat.branches[branch_id].messages)

    maybe_broadcast_monitoring(
      socket,
      {:new_message, %{chat_id: socket.assigns.chat_id, message: error_message_obj}}
    )

    socket
    |> assign(branched_chat: branched_chat)
    |> process_next_message_or_idle(branch_id)
    |> then(&{:noreply, &1})
  end

  ## Private Functions

  defp process_next_message_or_idle(socket, branch_id) do
    branched_chat = socket.assigns.branched_chat
    {next_message, branched_chat} = BranchedChat.dequeue_message(branched_chat, branch_id)

    if next_message do
      maybe_broadcast_monitoring(
        socket,
        {:new_message,
         %{
           chat_id: socket.assigns.chat_id,
           message: List.last(branched_chat.branches[branch_id].messages)
         }}
      )

      socket
      |> assign(branched_chat: branched_chat)
      |> start_llm_stream(branch_id, next_message)
    else
      socket |> assign(branched_chat: branched_chat)
    end
  end

  defp maybe_broadcast_monitoring(socket, event) do
    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(Cara.PubSub, "teacher:monitor", event)
    end

    socket
  end

  @spec do_send_message(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_send_message(message, socket) do
    if message_blank?(message) do
      {:noreply, socket}
    else
      socket = reset_message_form(socket)
      branched_chat = socket.assigns.branched_chat
      current_branch_id = branched_chat.current_branch_id

      if BranchedChat.busy?(branched_chat, current_branch_id) do
        branched_chat = BranchedChat.enqueue_message(branched_chat, current_branch_id, message)
        {:noreply, assign(socket, branched_chat: branched_chat)}
      else
        branched_chat = BranchedChat.add_user_message(branched_chat, message)

        maybe_broadcast_monitoring(
          socket,
          {:new_message,
           %{
             chat_id: socket.assigns.chat_id,
             message: List.last(BranchedChat.get_current_messages(branched_chat))
           }}
        )

        socket =
          socket
          |> assign(branched_chat: branched_chat)
          |> start_llm_stream(current_branch_id, message)

        {:noreply, socket}
      end
    end
  end

  defp message_blank?(message), do: String.trim(message) == ""

  @spec start_llm_stream(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp start_llm_stream(socket, branch_id, message) do
    branched_chat = BranchedChat.set_tool_status(socket.assigns.branched_chat, branch_id, "Thinking...")

    llm_call_params = %{
      message: message,
      llm_context: branched_chat.branches[branch_id].context,
      live_view_pid: self(),
      llm_tools: socket.assigns.llm_tools,
      chat_mod: chat_module(),
      tool_usage_counts: socket.assigns.tool_usage_counts,
      branch_id: branch_id
    }

    {:ok, pid} = ChatOrchestrator.run(llm_call_params)

    branched_chat = BranchedChat.set_active_task(branched_chat, branch_id, pid, message)
    assign(socket, branched_chat: branched_chat)
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
  end

  defp rebuild_context_from_messages(messages, branched_chat) do
    messages
    |> Enum.drop(1)
    |> Enum.filter(fn msg -> !Map.get(msg, :deleted, false) end)
    |> Enum.reduce(chat_module().reset_context(BranchedChat.get_current_context(branched_chat)), fn msg, acc ->
      case msg.sender do
        :user -> ReqLLM.Context.append(acc, ReqLLM.Context.user(msg.content))
        :assistant -> ReqLLM.Context.append(acc, ReqLLM.Context.assistant(msg.content))
      end
    end)
  end

  ## Layout & Tree Helpers (Delegated to BranchedChat)

  defp render_branch_tree(assigns, nodes, depth \\ 0) do
    assigns = assign(assigns, nodes: nodes, depth: depth)

    ~H"""
    <%= for node <- @nodes do %>
      <% branch = @branched_chat.branches[node.id] %>
      <div class="flex flex-col">
        <div class="flex items-center">
          <%= if @depth > 0 do %>
            <div class="flex-shrink-0 flex items-center h-full" style={"width: #{@depth * 20}px"}>
              <div class="w-full border-b-2 border-l-2 border-gray-200 rounded-bl-lg h-6 -mt-6"></div>
            </div>
          <% end %>
          <button
            phx-click="switch_branch"
            phx-value-id={node.id}
            class={"flex-1 text-left p-2 my-1 rounded-lg transition-all border #{if node.id == @branched_chat.current_branch_id, do: "bg-blue-50 border-blue-200 text-blue-700 shadow-sm", else: "bg-white border-transparent text-gray-700 hover:bg-gray-50 hover:border-gray-200"}"}
          >
            <div class="flex items-start gap-2">
              <span class={"hero-chat-bubble-bottom-center-text inline-block w-4 h-4 mt-0.5 #{if node.id == @branched_chat.current_branch_id, do: "text-blue-600", else: "text-gray-400"}"}>
              </span>
              <div class="flex-1 min-w-0">
                <div class={"text-xs font-semibold truncate #{if node.id == @branched_chat.current_branch_id, do: "text-blue-800", else: "text-gray-900"}"}>
                  {if branch.name == "", do: "New branch...", else: branch.name}
                </div>
              </div>
            </div>
          </button>
        </div>
        {render_branch_tree(assigns, node.children, @depth + 1)}
      </div>
    <% end %>
    """
  end

  ## Rendering Helpers

  @doc """
  Renders markdown content as safe HTML.

  This is primarily used in templates to render chat message content.
  """
  @spec render_markdown(String.t()) :: Phoenix.HTML.safe()
  def render_markdown(content) do
    MDEx.new(markdown: content)
    |> MDExGFM.attach()
    |> MDExMermaid.attach(
      # already initialized in app.js
      mermaid_init: "",
      mermaid_pre_attrs: fn seq ->
        ~s(id="mermaid-#{seq}" class="mermaid" phx-hook="MermaidHook" phx-update="ignore")
      end
    )
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end

  @spec app_version() :: String.t()
  defp app_version do
    Application.spec(:cara, :vsn) |> to_string
  end
end
