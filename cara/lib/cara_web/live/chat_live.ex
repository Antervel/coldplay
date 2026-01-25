defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view

  alias Cara.AI.Chat
  alias MDEx


  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      chat_messages: [],
      llm_context: Chat.new_context(),
      message_data: %{"message" => ""}
    )}
  end

  @impl true
  def handle_event("send_message", %{"chat" => %{"message" => message}}, socket) do
    # Add user message to chat history immediately
    updated_chat_messages = socket.assigns.chat_messages ++ [%{sender: :user, content: message}]
    
    # Assign the updated chat messages to the socket and pass this new socket to send_message_to_llm
    socket = assign(socket, chat_messages: updated_chat_messages)

    # Call LLM logic and get the updated socket
    new_socket = send_message_to_llm(message, socket)

    # Reset the form by updating message_data in the returned socket
    {:noreply, assign(new_socket, message_data: %{"message" => ""})}
  end

  @impl true
  def handle_event("validate", %{"chat" => params}, socket) do
    updated_message_data = Map.merge(socket.assigns.message_data, params)
    {:noreply, assign(socket, message_data: updated_message_data)}
  end

  # Handle streamed chunks from the LLM
  @impl true
  def handle_info({:llm_chunk, chunk}, socket) do
    # Append chunk to the last message, or start a new assistant message
    updated_messages =
      case Enum.reverse(socket.assigns.chat_messages) do
        [%{sender: :assistant, content: existing_content} | rest] ->
          Enum.reverse([%{sender: :assistant, content: existing_content <> chunk} | rest])
        _ ->
          socket.assigns.chat_messages ++ [%{sender: :assistant, content: chunk}]
      end
    
    {:noreply, assign(socket, chat_messages: updated_messages)}
  end

  # Handle end of LLM stream
  @impl true
  def handle_info({:llm_end, llm_context_builder}, socket) do
    # Get the final assistant message content to pass to the context builder
    final_assistant_message_content =
      case Enum.reverse(socket.assigns.chat_messages) do
        [%{sender: :assistant, content: final_content} | _rest] -> final_content
        _ -> "" # Should not happen if chunks were received
      end

    updated_llm_context = llm_context_builder.(final_assistant_message_content)
    {:noreply, assign(socket, llm_context: updated_llm_context)}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-100">
      <header class="bg-blue-600 text-white p-4 shadow-md">
        <h1 class="text-2xl font-semibold">AI Chat</h1>
      </header>

      <main class="flex-1 overflow-y-auto p-4 space-y-4">
        <%= for message <- @chat_messages do %>
          <div classs={ "flex #{if message.sender == :user, do: "justify-end", else: "justify-start"}" }>
            <div class={ "max-w-xl p-3 rounded-lg shadow-md #{if message.sender == :user, do: "bg-blue-500 text-white", else: "bg-gray-300 text-gray-800"}" }>
              <%= if message.sender == :assistant do %>
                <%= case MDEx.to_html(message.content, sanitize: MDEx.Document.default_sanitize_options()) do
                      {:ok, html_string} -> Phoenix.HTML.raw(html_string)
                      {:error, _} -> "Error rendering Markdown." # Fallback for error
                    end %>
              <% else %>
                <%= message.content %>
              <% end %>
            </div>
          </div>
        <% end %>
      </main>

      <footer class="bg-white p-4 shadow-md">
        <.form :let={f} for={to_form(@message_data, as: :chat)} phx-submit="send_message" phx-hook="ChatScroll">
          <div class="flex space-x-2">
            <.input field={f[:message]} type="text"
              placeholder="Type your message..."
              phx-change="validate"
              autocomplete="off"
              class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-400 text-gray-800" />
            <button type="submit" class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-400">Send</button>
          </div>
        </.form>
      </footer>
    </div>
    """
  end

  defp send_message_to_llm(message, socket) do
    # Call LLM in a separate task to avoid blocking the LiveView process
    live_view_pid = self()
    Task.start(fn ->
      case Chat.send_message_stream(message, socket.assigns.llm_context) do
        {:ok, stream, llm_context_builder} ->
          # Send back initial message to start a new bubble for assistant
          send(live_view_pid, {:llm_chunk, ""})
          Enum.each(stream, fn chunk ->
            # Send chunks back to the LiveView process
            send(live_view_pid, {:llm_chunk, chunk})
          end)
          # Send an end message with the context builder
          send(live_view_pid, {:llm_end, llm_context_builder})
        {:error, reason} ->
          # Handle error, maybe send an error message to the LiveView
          send(live_view_pid, {:llm_chunk, ""}) # Start a new bubble for error
          send(live_view_pid, {:llm_chunk, "Error: #{inspect(reason)}"})
          send(live_view_pid, {:llm_end, fn(_)-> socket.assigns.llm_context end}) # Pass original context on error
      end
    end)
    socket # Return the socket
  end
end
