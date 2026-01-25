defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view

  alias Cara.AI.Chat
  alias MDEx

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       chat_messages: [],
       llm_context: Chat.new_context(),
       message_data: %{"message" => ""}
     )}
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

  # Handle streamed chunks from the LLM
  @impl true
  def handle_info({:llm_chunk, chunk}, socket) do
    # Append chunk to the last message, or start a new assistant message
    updated_messages =
      case Enum.reverse(socket.assigns.chat_messages) do
        [%{sender: :assistant, content: existing_content} | rest] ->
          Enum.reverse([%{sender: :assistant, content: existing_content <> chunk} | rest])

        # ONLY CREATE NEW MESSAGE IF CHUNK IS NOT EMPTY
        _ when chunk != "" ->
          socket.assigns.chat_messages ++ [%{sender: :assistant, content: chunk}]

        # If chunk is empty and no assistant message to append to, do nothing
        _ ->
          socket.assigns.chat_messages
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
        # Should not happen if chunks were received
        _ -> ""
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

      <main id="chat-messages" phx-hook="ChatScroll" class="flex-1 overflow-y-auto p-4 space-y-4">
        <%= for message <- @chat_messages do %>
          <div classs={ "flex #{if message.sender == :user, do: "justify-end", else: "justify-start"}" }>
            <div class={ "max-w-xl p-3 rounded-lg shadow-md #{if message.sender == :user, do: "bg-blue-500 text-white", else: "bg-gray-300 text-gray-800"}" }>
              {case MDEx.to_html(message.content, sanitize: MDEx.Document.default_sanitize_options()) do
                {:ok, html_string} -> Phoenix.HTML.raw(html_string)
                # Fallback for error
                {:error, _} -> "Error rendering Markdown."
              end}
            </div>
          </div>
        <% end %>
      </main>

      <footer class="bg-white p-4 shadow-md">
        <.form
          :let={f}
          for={to_form(@message_data, as: :chat)}
          phx-submit="submit_message"
          phx-hook="ChatScroll"
          id="chat-form"
        >
          <div class="flex items-end">
            <textarea
              name={f[:message].name}
              id={f[:message].id}
              placeholder="Type your message..."
              phx-change="validate"
              phx-hook="ChatInput"
              rows="1"
              class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-400 text-gray-800 resize-none overflow-hidden"
              value={f[:message].value}
            ></textarea>
            <button
              type="submit"
              class="ml-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-400"
            >
              Send
            </button>
          </div>
        </.form>
      </footer>
    </div>
    """
  end

  defp do_send_message(message, socket) do
    if String.trim(message) != "" do
      # Add user message to chat history immediately
      updated_chat_messages = socket.assigns.chat_messages ++ [%{sender: :user, content: message}]

      # Assign the updated chat messages to the socket and pass this new socket to send_message_to_llm
      socket = assign(socket, chat_messages: updated_chat_messages)

      # Call LLM logic and get the updated socket
      new_socket = send_message_to_llm(message, socket)

      # Reset the form by updating message_data in the returned socket
      {:noreply, assign(new_socket, message_data: %{"message" => ""})}
    else
      # If message is empty, don't send
      {:noreply, socket}
    end
  end

  defp send_message_to_llm(message, socket) do
    # Call LLM in a separate task to avoid blocking the LiveView process
    live_view_pid = self()

    Task.start(fn ->
      case Chat.send_message_stream(message, socket.assigns.llm_context) do
        {:ok, stream, llm_context_builder} ->
          sent_any_chunks =
            Enum.reduce_while(stream, false, fn chunk, _acc ->
              send(live_view_pid, {:llm_chunk, chunk})
              # Continue and set flag to true
              {:cont, true}
            end)

          if sent_any_chunks do
            send(live_view_pid, {:llm_end, llm_context_builder})
          else
            # Stream returned {:ok, ...} but sent no chunks (silent failure, likely rate limit)
            # We assume it's a rate limit error based on observed behavior.
            user_message = "The AI is busy. Wait a moment and try again later."
            send(live_view_pid, {:llm_chunk, user_message})
            send(live_view_pid, {:llm_end, fn _ -> socket.assigns.llm_context end})
          end

        {:error, %ReqLLM.Error.API.Request{status: 429, response_body: response_body}} ->
          retry_delay_message =
            case Enum.find(response_body["details"] || [], fn detail ->
                   Map.get(detail, "@type") == "type.googleapis.com/google.rpc.RetryInfo"
                 end) do
              %{"retryDelay" => delay} when is_binary(delay) ->
                " Please retry in #{delay}."

              _ ->
                ""
            end

          user_message = "The AI is busy. Wait a moment and try again later." <> retry_delay_message
          send(live_view_pid, {:llm_chunk, user_message})
          send(live_view_pid, {:llm_end, fn _ -> socket.assigns.llm_context end})

        {:error, reason} ->
          send(live_view_pid, {:llm_chunk, "Error: #{inspect(reason)}"})
          send(live_view_pid, {:llm_end, fn _ -> socket.assigns.llm_context end})
      end
    end)

    # Return the socket
    socket
  end
end
