defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  require Logger

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

        initial_branch_id = "main"
        initial_messages = [welcome_message_for_student(info)]
        initial_context = chat_module().new_context(system_prompt)

        branches = %{
          initial_branch_id => %{
            name: "Main Conversation",
            messages: initial_messages,
            context: initial_context
          }
        }

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
           branches: branches,
           branch_ids: [initial_branch_id],
           current_branch_id: initial_branch_id,
           show_branches: false,
           chat_messages: initial_messages,
           llm_context: initial_context,
           message_data: %{"message" => ""},
           app_version: app_version(),
           student_info: info,
           llm_tools: llm_tools,
           tool_status: nil,
           bubble_width: bubble_width,
           tool_usage_counts:
             Enum.reduce(llm_tools, %{}, fn tool, acc ->
               Map.put(acc, tool.name, 0)
             end),
           active_task: nil,
           pending_messages: [],
           current_user_message: nil,
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
    {:noreply, assign(socket, show_branches: !socket.assigns.show_branches)}
  end

  @impl true
  def handle_event("switch_branch", %{"id" => id}, socket) do
    case Map.get(socket.assigns.branches, id) do
      nil ->
        {:noreply, socket}

      branch ->
        socket =
          assign(socket,
            current_branch_id: id,
            chat_messages: branch.messages,
            llm_context: branch.context
          )

        if monitoring_enabled?() do
          Phoenix.PubSub.broadcast(
            Cara.PubSub,
            "teacher:monitor",
            {:chat_state,
             %{
               id: socket.assigns.chat_id,
               student: socket.assigns.student_info,
               messages: socket.assigns.chat_messages
             }}
          )
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("branch_off", %{"id" => id}, socket) do
    # Find the message index
    messages = socket.assigns.chat_messages
    idx = Enum.find_index(messages, fn msg -> msg.id == id end)

    if idx do
      # Slice messages up to the selected one
      # We include the selected message in the new branch
      new_messages = Enum.slice(messages, 0..idx)

      # Rebuild llm_context from new_messages
      # Similar to delete_message, skip welcome message
      new_llm_context =
        new_messages
        |> Enum.drop(1)
        |> Enum.filter(fn msg -> !Map.get(msg, :deleted, false) end)
        |> Enum.reduce(chat_module().reset_context(socket.assigns.llm_context), fn msg, acc ->
          case msg.sender do
            :user -> ReqLLM.Context.append(acc, ReqLLM.Context.user(msg.content))
            :assistant -> ReqLLM.Context.append(acc, ReqLLM.Context.assistant(msg.content))
          end
        end)

      # Create new branch ID and name
      new_branch_id = Ecto.UUID.generate()

      # Use a snippet of the message as name
      last_msg = Enum.at(new_messages, -1)
      prefix = if last_msg.sender == :user, do: "You: ", else: "Cara: "

      snippet =
        last_msg.content
        |> String.slice(0, 30)
        |> String.trim()

      snippet = if String.length(last_msg.content) > 30, do: snippet <> "...", else: snippet
      new_branch_name = "#{prefix}\"#{snippet}\""

      new_branch = %{
        name: new_branch_name,
        messages: new_messages,
        context: new_llm_context
      }

      branches = Map.put(socket.assigns.branches, new_branch_id, new_branch)

      socket =
        assign(socket,
          branches: branches,
          branch_ids: socket.assigns.branch_ids ++ [new_branch_id],
          current_branch_id: new_branch_id,
          chat_messages: new_messages,
          llm_context: new_llm_context,
          show_branches: true
        )

      if monitoring_enabled?() do
        Phoenix.PubSub.broadcast(
          Cara.PubSub,
          "teacher:monitor",
          {:chat_state,
           %{
             id: socket.assigns.chat_id,
             student: socket.assigns.student_info,
             messages: socket.assigns.chat_messages
           }}
        )
      end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_notes", _params, socket) do
    {:noreply, assign(socket, show_notes: !socket.assigns.show_notes)}
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
    updated_chat_messages =
      Enum.map(socket.assigns.chat_messages, fn msg ->
        if msg.id == id do
          %{msg | deleted: true}
        else
          msg
        end
      end)

    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(
        Cara.PubSub,
        "teacher:monitor",
        {:message_deleted, %{chat_id: socket.assigns.chat_id, message_id: id}}
      )
    end

    # Rebuild llm_context from updated_chat_messages
    # We skip the first message because it's the welcome message (not in llm_context)
    # We use chat_module().reset_context(socket.assigns.llm_context) to get a fresh context
    # with just the system prompt.
    new_llm_context =
      updated_chat_messages
      |> Enum.drop(1)
      |> Enum.filter(fn msg -> !msg.deleted end)
      |> Enum.reduce(chat_module().reset_context(socket.assigns.llm_context), fn msg, acc ->
        case msg.sender do
          :user -> ReqLLM.Context.append(acc, ReqLLM.Context.user(msg.content))
          :assistant -> ReqLLM.Context.append(acc, ReqLLM.Context.assistant(msg.content))
        end
      end)

    {:noreply,
     assign(socket,
       chat_messages: updated_chat_messages,
       llm_context: new_llm_context
     )
     |> sync_current_branch()}
  end

  # Fallback for old clients (should not happen if refreshed, but for safety)
  def handle_event("delete_message", %{"idx" => idx}, socket) do
    idx = if is_binary(idx), do: String.to_integer(idx), else: idx
    msg_to_delete = Enum.at(socket.assigns.chat_messages, idx)

    if msg_to_delete do
      handle_event("delete_message", %{"id" => msg_to_delete.id}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    if pid = socket.assigns.active_task do
      Process.exit(pid, :kill)
    end

    {updated_llm_context, updated_chat_messages} =
      if user_msg = socket.assigns.current_user_message do
        {partial_content, updated_messages} =
          case List.last(socket.assigns.chat_messages) do
            %{sender: :assistant, content: content} ->
              {content, socket.assigns.chat_messages}

            _ ->
              cancelled_msg = %{
                sender: :assistant,
                content: "*Cancelled*",
                id: Ecto.UUID.generate(),
                deleted: false
              }

              {"*Cancelled*", socket.assigns.chat_messages ++ [cancelled_msg]}
          end

        # If we appended a "Cancelled" message, we should broadcast it
        cancelled_msg_obj = List.last(updated_messages)

        if cancelled_msg_obj.content == "*Cancelled*" and monitoring_enabled?() do
          Phoenix.PubSub.broadcast(
            Cara.PubSub,
            "teacher:monitor",
            {:new_message, %{chat_id: socket.assigns.chat_id, message: cancelled_msg_obj}}
          )
        end

        new_ctx =
          socket.assigns.llm_context
          |> ReqLLM.Context.append(ReqLLM.Context.user(user_msg))
          |> ReqLLM.Context.append(ReqLLM.Context.assistant(partial_content))

        {new_ctx, updated_messages}
      else
        {socket.assigns.llm_context, socket.assigns.chat_messages}
      end

    {:noreply,
     assign(socket,
       active_task: nil,
       pending_messages: [],
       tool_status: nil,
       current_user_message: nil,
       llm_context: updated_llm_context,
       chat_messages: updated_chat_messages
     )
     |> sync_current_branch()}
  end

  defp sync_current_branch(socket) do
    current_branch = socket.assigns.branches[socket.assigns.current_branch_id]
    updated_branch = %{current_branch | messages: socket.assigns.chat_messages, context: socket.assigns.llm_context}
    branches = Map.put(socket.assigns.branches, socket.assigns.current_branch_id, updated_branch)
    assign(socket, branches: branches)
  end

  @impl true
  def handle_info({:teacher_joined, _}, socket) do
    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(
        Cara.PubSub,
        "teacher:monitor",
        {:chat_state,
         %{
           id: socket.assigns.chat_id,
           student: socket.assigns.student_info,
           messages: socket.assigns.chat_messages
         }}
      )
    end

    {:noreply, socket}
  end

  # Handle streamed chunks from the LLM
  @impl true
  def handle_info({:llm_chunk, chunk}, socket) when is_binary(chunk) do
    updated_messages = append_chunk_to_messages(chunk, socket.assigns.chat_messages)

    {:noreply,
     assign(socket, chat_messages: updated_messages, tool_status: nil)
     |> sync_current_branch()}
  end

  # Handle end of LLM stream. Send the `llm_end` event to javascript so Mermaid runs
  @impl true
  def handle_info({:llm_end, llm_context_builder}, socket) when is_function(llm_context_builder, 1) do
    final_content = get_last_assistant_message_content(socket.assigns.chat_messages)
    updated_llm_context = llm_context_builder.(final_content)

    # Broadcast the completed AI message
    final_message = List.last(socket.assigns.chat_messages)

    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(
        Cara.PubSub,
        "teacher:monitor",
        {:new_message, %{chat_id: socket.assigns.chat_id, message: final_message}}
      )
    end

    socket =
      socket
      |> push_event("llm_end", %{})
      |> process_next_message_or_idle(updated_llm_context)
      |> sync_current_branch()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:llm_status, status}, socket) do
    {:noreply, assign(socket, tool_status: status)}
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
  def handle_info({:llm_error, error_message}, socket) when is_binary(error_message) do
    error_message_obj = %{
      sender: :assistant,
      content: error_message,
      id: Ecto.UUID.generate(),
      deleted: false
    }

    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(
        Cara.PubSub,
        "teacher:monitor",
        {:new_message, %{chat_id: socket.assigns.chat_id, message: error_message_obj}}
      )
    end

    socket = assign(socket, chat_messages: socket.assigns.chat_messages ++ [error_message_obj])
    {:noreply, process_next_message_or_idle(socket) |> sync_current_branch()}
  end

  ## Private Functions

  defp process_next_message_or_idle(socket, updated_llm_context \\ nil) do
    socket = if updated_llm_context, do: assign(socket, llm_context: updated_llm_context), else: socket

    case socket.assigns.pending_messages do
      [next_message | rest] ->
        socket = add_user_message_to_chat(socket, next_message)

        # Broadcast the user message
        maybe_broadcast_monitoring(
          socket,
          {:new_message, %{chat_id: socket.assigns.chat_id, message: List.last(socket.assigns.chat_messages)}}
        )

        socket
        |> assign(pending_messages: rest, current_user_message: next_message, tool_status: "Thinking...")
        |> start_llm_stream(next_message)

      [] ->
        assign(socket, active_task: nil, current_user_message: nil, tool_status: nil)
    end
  end

  defp maybe_broadcast_monitoring(socket, event) do
    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(Cara.PubSub, "teacher:monitor", event)
    end

    socket
  end

  ## Message Processing Helpers

  @spec append_chunk_to_messages(String.t(), [chat_message()]) :: [chat_message()]
  defp append_chunk_to_messages("", messages), do: messages

  defp append_chunk_to_messages(chunk, messages) do
    case List.last(messages) do
      %{sender: :assistant} ->
        {last, rest} = List.pop_at(messages, -1)
        rest ++ [%{last | content: last.content <> chunk}]

      _ ->
        messages ++
          [%{sender: :assistant, content: chunk, id: Ecto.UUID.generate(), deleted: false}]
    end
  end

  @spec get_last_assistant_message_content([chat_message()]) :: String.t()
  defp get_last_assistant_message_content(messages) do
    %{sender: :assistant, content: content} = List.last(messages)
    content
  end

  @spec do_send_message(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_send_message(message, socket) do
    if message_blank?(message) do
      {:noreply, socket}
    else
      socket = reset_message_form(socket)

      if socket.assigns.active_task do
        {:noreply,
         assign(socket, pending_messages: socket.assigns.pending_messages ++ [message])
         |> sync_current_branch()}
      else
        socket = add_user_message_to_chat(socket, message)

        # Broadcast the user message
        maybe_broadcast_monitoring(
          socket,
          {:new_message,
           %{chat_id: socket.assigns.chat_id, message: List.last(socket.assigns.chat_messages)}}
        )

        socket =
          socket
          |> assign(tool_status: "Thinking...", current_user_message: message)
          |> start_llm_stream(message)
          |> sync_current_branch()

        {:noreply, socket}
      end
    end
  end

  defp message_blank?(message), do: String.trim(message) == ""

  @spec add_user_message_to_chat(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp add_user_message_to_chat(socket, message) do
    user_message = %{
      sender: :user,
      content: message,
      id: Ecto.UUID.generate(),
      deleted: false
    }

    assign(socket, chat_messages: socket.assigns.chat_messages ++ [user_message])
  end

  @spec start_llm_stream(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp start_llm_stream(socket, message) do
    llm_call_params = %{
      message: message,
      llm_context: socket.assigns.llm_context,
      live_view_pid: self(),
      llm_tools: socket.assigns.llm_tools,
      chat_mod: chat_module(),
      tool_usage_counts: socket.assigns.tool_usage_counts
    }

    {:ok, pid} = ChatOrchestrator.run(llm_call_params)

    assign(socket, active_task: pid)
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
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
