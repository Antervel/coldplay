defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  use Retry

  @type chat_message :: %{sender: :user | :assistant, content: String.t()}
  @type message_data :: %{String.t() => String.t()}

  # Get the chat module from config at runtime (allows switching to mock in tests)
  defp chat_module do
    Application.get_env(:cara, :chat_module, Cara.AI.Chat)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       chat_messages: [],
       llm_context: chat_module().new_context(),
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
    final_content = get_last_assistant_message_content(socket.assigns.chat_messages)
    updated_llm_context = llm_context_builder.(final_content)
    {:noreply, assign(socket, llm_context: updated_llm_context)}
  end

  # Handle LLM errors
  @impl true
  def handle_info({:llm_error, error_message}, socket) when is_binary(error_message) do
    error_message_obj = %{sender: :assistant, content: error_message}
    {:noreply, assign(socket, chat_messages: socket.assigns.chat_messages ++ [error_message_obj])}
  end

  ## Private Functions

  @spec do_send_message(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_send_message(message, socket) do
    if message_blank?(message) do
      {:noreply, socket}
    else
      socket
      |> add_user_message_to_chat(message)
      |> start_llm_stream(message)
      |> reset_message_form()
      |> then(&{:noreply, &1})
    end
  end

  defp message_blank?(message), do: String.trim(message) == ""

  @spec add_user_message_to_chat(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp add_user_message_to_chat(socket, message) do
    user_message = %{sender: :user, content: message}
    assign(socket, chat_messages: socket.assigns.chat_messages ++ [user_message])
  end

  @spec start_llm_stream(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp start_llm_stream(socket, message) do
    live_view_pid = self()
    llm_context = socket.assigns.llm_context

    Task.start(fn ->
      retry with: constant_backoff(100) |> Stream.take(10) do
        process_llm_request(message, llm_context, live_view_pid)
      end
    end)

    socket
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
  end

  @spec process_llm_request(String.t(), term(), pid()) :: :ok | :retry
  defp process_llm_request(message, llm_context, live_view_pid) do
    chat_mod = Application.get_env(:cara, :chat_module, Cara.AI.Chat)

    with {:ok, stream, llm_context_builder} <- chat_mod.send_message_stream(message, llm_context),
         true <- process_stream(stream, live_view_pid, llm_context_builder) do
      :ok
    else
      {:error, reason} ->
        send(live_view_pid, {:llm_error, "Error: #{inspect(reason)}"})
        :error

      false ->
        send(live_view_pid, {:llm_error, "The AI did not return a response. Please try again."})
        :error
    end
  rescue
    exception ->
      error_message = format_exception_message(exception)
      send(live_view_pid, {:llm_error, error_message})
      :error
  end

  defp process_stream(stream, live_view_pid, llm_context_builder) do
    sent_any_chunks =
      Enum.reduce_while(stream, false, fn chunk, _acc ->
        send(live_view_pid, {:llm_chunk, chunk})
        {:cont, true}
      end)

    if sent_any_chunks do
      send(live_view_pid, {:llm_end, llm_context_builder})
    end

    sent_any_chunks
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
  defp append_chunk_to_messages("", messages), do: messages

  defp append_chunk_to_messages(chunk, messages) do
    case List.last(messages) do
      %{sender: :assistant} ->
        {last, rest} = List.pop_at(messages, -1)
        rest ++ [%{last | content: last.content <> chunk}]

      _ ->
        messages ++ [%{sender: :assistant, content: chunk}]
    end
  end

  @spec get_last_assistant_message_content([chat_message()]) :: String.t()
  defp get_last_assistant_message_content(messages) do
    case List.last(messages) do
      %{sender: :assistant, content: content} -> content
      _ -> ""
    end
  end

  ## Rendering Helpers

  @doc """
  Renders markdown content as safe HTML.

  This is primarily used in templates to render chat message content.
  """
  @spec render_markdown(String.t()) :: Phoenix.HTML.safe()
  def render_markdown(content) do
    content
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end
end
