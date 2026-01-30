defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view

  alias Cara.AI.Chat

  @type chat_message :: %{sender: :user | :assistant, content: String.t()}
  @type message_data :: %{String.t() => String.t()}

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
  def handle_info({:llm_chunk, chunk}, socket) when is_binary(chunk) do
    updated_messages = append_chunk_to_messages(chunk, socket.assigns.chat_messages)
    {:noreply, assign(socket, chat_messages: updated_messages)}
  end

  # Handle end of LLM stream
  @impl true
  def handle_info({:llm_end, llm_context_builder}, socket) when is_function(llm_context_builder, 1) do
    final_content = get_final_assistant_content(socket.assigns.chat_messages)
    updated_llm_context = llm_context_builder.(final_content)
    {:noreply, assign(socket, llm_context: updated_llm_context)}
  end

  # Handle LLM errors
  @impl true
  def handle_info({:llm_error, error_message}, socket) when is_binary(error_message) do
    error_messages = socket.assigns.chat_messages ++ [%{sender: :assistant, content: error_message}]
    {:noreply, assign(socket, chat_messages: error_messages)}
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
          <div class={"flex #{if message.sender == :user, do: "justify-end", else: "justify-start"}"}>
            <div class={"max-w-xl p-3 rounded-lg shadow-md #{if message.sender == :user, do: "bg-blue-500 text-white", else: "bg-gray-300 text-gray-800"}"}>
              {render_markdown(message.content)}
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

  ## Private Functions

  @spec do_send_message(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_send_message(message, socket) do
    if String.trim(message) != "" do
      socket
      |> add_user_message_to_chat(message)
      |> start_llm_stream(message)
      |> reset_message_form()
      |> then(&{:noreply, &1})
    else
      {:noreply, socket}
    end
  end

  @spec add_user_message_to_chat(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp add_user_message_to_chat(socket, message) do
    user_message = %{sender: :user, content: message}
    updated_messages = socket.assigns.chat_messages ++ [user_message]
    assign(socket, chat_messages: updated_messages)
  end

  @spec start_llm_stream(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp start_llm_stream(socket, message) do
    live_view_pid = self()
    llm_context = socket.assigns.llm_context

    Task.start(fn ->
      process_llm_request(message, llm_context, live_view_pid)
    end)

    socket
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
  end

  @spec process_llm_request(String.t(), term(), pid()) :: :ok
  defp process_llm_request(message, llm_context, live_view_pid) do
    try do
      {:ok, stream, llm_context_builder} = Chat.send_message_stream(message, llm_context)

      sent_any_chunks =
        Enum.reduce_while(stream, false, fn chunk, _acc ->
          send(live_view_pid, {:llm_chunk, chunk})
          {:cont, true}
        end)

      if sent_any_chunks do
        send(live_view_pid, {:llm_end, llm_context_builder})
      else
        send(live_view_pid, {:llm_error, "The AI did not return a response. Please try again."})
      end

      :ok
    rescue
      exception ->
        error_message = format_exception_message(exception)
        send(live_view_pid, {:llm_error, error_message})
        :ok
    end
  end

  @spec format_exception_message(Exception.t()) :: String.t()
  defp format_exception_message(%{__struct__: ReqLLM.Error.API.Request, status: 429, response_body: response_body}) do
    retry_delay = extract_retry_delay(response_body)
    base_message = "The AI is busy. Wait a moment and try again later."

    case retry_delay do
      nil -> base_message
      delay -> base_message <> " Please retry in #{delay}."
    end
  end

  defp format_exception_message(%{__struct__: ReqLLM.Error.API.Request, status: status}) do
    "API error (status #{status}). Please try again."
  end

  defp format_exception_message(exception) do
    "Error: #{Exception.message(exception)}"
  end

  @spec extract_retry_delay(map()) :: String.t() | nil
  defp extract_retry_delay(response_body) do
    details = Map.get(response_body, "details", [])

    case Enum.find(details, &retry_info?/1) do
      %{"retryDelay" => delay} when is_binary(delay) -> delay
      _ -> nil
    end
  end

  @spec retry_info?(map()) :: boolean()
  defp retry_info?(detail) do
    Map.get(detail, "@type") == "type.googleapis.com/google.rpc.RetryInfo"
  end

  ## Message Processing Helpers

  @spec append_chunk_to_messages(String.t(), [chat_message()]) :: [chat_message()]
  defp append_chunk_to_messages(chunk, messages) do
    case {chunk, Enum.reverse(messages)} do
      {"", _} ->
        messages

      {chunk, [%{sender: :assistant, content: existing_content} | rest]} ->
        updated_message = %{sender: :assistant, content: existing_content <> chunk}
        Enum.reverse([updated_message | rest])

      {chunk, _} ->
        messages ++ [%{sender: :assistant, content: chunk}]
    end
  end

  @spec get_final_assistant_content([chat_message()]) :: String.t()
  defp get_final_assistant_content(messages) do
    case Enum.reverse(messages) do
      [%{sender: :assistant, content: final_content} | _rest] -> final_content
      _ -> ""
    end
  end

  ## Rendering Helpers

  @spec render_markdown(String.t()) :: Phoenix.HTML.safe()
  defp render_markdown(content) do
    case MDEx.to_html(content, sanitize: MDEx.Document.default_sanitize_options()) do
      {:ok, html_string} -> Phoenix.HTML.raw(html_string)
      {:error, _} -> Phoenix.HTML.raw("Error rendering Markdown.")
    end
  end
end
