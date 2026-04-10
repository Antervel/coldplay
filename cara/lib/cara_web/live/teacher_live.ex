defmodule CaraWeb.TeacherLive do
  use CaraWeb, :live_view

  alias Cara.Education.Monitoring

  @impl true
  def mount(_params, _session, socket) do
    monitoring_enabled = Application.get_env(:cara, :enable_teacher_monitoring, true)

    if connected?(socket) and monitoring_enabled do
      Phoenix.PubSub.subscribe(Cara.PubSub, "teacher:monitor")
      Monitoring.teacher_joined()
    end

    {:ok,
     assign(socket,
       chats: %{},
       page_title: "Teacher Dashboard",
       monitoring_enabled: monitoring_enabled
     )}
  end

  @impl true
  def handle_info({:chat_started, %{id: id, student: student}}, socket) do
    # If chat already exists, we might want to keep the history
    # instead of clearing it (student reloaded, but we have history)
    chats =
      Map.update(socket.assigns.chats, id, %{id: id, student: student, messages: []}, fn chat ->
        %{chat | student: student}
      end)

    {:noreply, assign(socket, chats: chats)}
  end

  @impl true
  def handle_info({:chat_left, %{id: id}}, socket) do
    chats = Map.delete(socket.assigns.chats, id)
    {:noreply, assign(socket, chats: chats)}
  end

  @impl true
  def handle_info({:chat_state, %{id: id, student: student, messages: messages}}, socket) do
    # Received full state from a student session
    new_chat = %{
      id: id,
      student: student,
      messages: messages
    }

    chats = Map.put(socket.assigns.chats, id, new_chat)
    {:noreply, assign(socket, chats: chats)}
  end

  @impl true
  def handle_info({:new_message, %{chat_id: chat_id, message: message}}, socket) do
    chats =
      Map.update(socket.assigns.chats, chat_id, nil, fn chat ->
        # Avoid duplicate messages if we get them via state sync + new_message
        # But here we just append. To be safe, we could check ID.
        # For now, simple append.
        %{chat | messages: chat.messages ++ [message]}
      end)

    # If chat didn't exist (race condition), we ignore or could ask for state?
    # Ignoring for now as state sync should handle it.
    chats = if chats[chat_id], do: chats, else: socket.assigns.chats

    {:noreply, assign(socket, chats: chats)}
  end

  @impl true
  def handle_info({:message_deleted, %{chat_id: chat_id, message_id: message_id}}, socket) do
    chats =
      Map.update(socket.assigns.chats, chat_id, nil, fn chat ->
        %{chat | messages: mark_deleted(chat.messages, message_id)}
      end)

    {:noreply, assign(socket, chats: chats)}
  end

  # Ignore other messages (like broadcasted from self)
  @impl true
  def handle_info({:teacher_joined, _}, socket), do: {:noreply, socket}

  defp mark_deleted(messages, message_id) do
    Enum.map(messages, fn msg ->
      if msg.id == message_id do
        %{msg | deleted: true}
      else
        msg
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 p-8">
      <h1 class="text-3xl font-bold mb-8 text-gray-800">Teacher Dashboard</h1>

      <%= if @monitoring_enabled do %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for {chat_id, chat} <- @chats do %>
            <div class="bg-white rounded-lg shadow-md flex flex-col h-[500px] overflow-hidden">
              <div class="bg-blue-600 text-white p-4">
                <h2 class="font-bold text-lg">{chat.student.name}</h2>
                <p class="text-sm opacity-80">{chat.student.subject} • {chat.student.age} years old</p>
              </div>

              <div class="flex-1 overflow-y-auto p-4 space-y-4 bg-gray-50">
                <%= for message <- chat.messages do %>
                  <div class={"flex flex-col #{if message.sender == :user, do: "items-end", else: "items-start"}"}>
                    <div class={"max-w-[85%] rounded-lg p-3 text-sm #{message_class(message)}"}>
                      <%= if Map.get(message, :deleted, false) do %>
                        <div class="text-xs font-bold uppercase mb-1 opacity-70">Deleted by student</div>
                        <div class="line-through opacity-60">
                          {render_markdown(message.content)}
                        </div>
                      <% else %>
                        {render_markdown(message.content)}
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if Enum.empty?(@chats) do %>
            <div class="col-span-full text-center py-20 text-gray-500">
              <p class="text-xl">No active students.</p>
              <p class="text-sm">Waiting for students to join...</p>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-20 text-gray-500 bg-white rounded-lg shadow-md">
          <p class="text-xl font-bold text-red-600">Monitoring is disabled.</p>
          <p class="text-sm mt-2">
            Please enable <code>:enable_teacher_monitoring</code> in your configuration to use this dashboard.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp message_class(message) do
    base =
      if message.sender == :user,
        do: "bg-yellow-100 text-gray-800",
        else: "bg-white border border-gray-200 text-gray-800"

    if Map.get(message, :deleted, false) do
      "bg-red-50 border border-red-200 text-red-800"
    else
      base
    end
  end

  def render_markdown(content) do
    MDEx.new(markdown: content)
    |> MDExGFM.attach()
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end
end
