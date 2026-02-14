defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  use Retry
  alias Cara.AI.ToolHandler
  alias Cara.AI.Tools.Calculator
  alias ReqLLM.Context

  @type chat_message :: %{sender: :user | :assistant, content: String.t()}
  @type message_data :: %{String.t() => String.t()}

  # Get the chat module from config at runtime (allows switching to mock in tests)
  defp chat_module do
    Application.get_env(:cara, :chat_module, Cara.AI.Chat)
  end

  defp render_greeting_prompt(student_info) do
    assigns = [
      name: student_info.name,
      subject: student_info.subject,
      age: student_info.age
    ]

    prompt_path = Path.join(:code.priv_dir(:cara), "prompts/greeting.eex")
    EEx.eval_file(prompt_path, assigns)
  end

  defp welcome_message_for_student(%{name: name, subject: subject}) do
    %{sender: :assistant, content: "Hello **#{name}**! Let's learn about #{subject} together! 🎓"}
  end

  @impl true
  def mount(_params, session, socket) do
    case Map.get(session, "student_info") do
      %{name: _name, subject: _subject, age: _age} = info ->
        system_prompt = render_greeting_prompt(info)
        calculator_tool = Calculator.calculator_tool()

        {:ok,
         assign(socket,
           chat_messages: [welcome_message_for_student(info)],
           llm_context: chat_module().new_context(system_prompt),
           message_data: %{"message" => ""},
           app_version: app_version(),
           student_info: info,
           llm_tools: [calculator_tool]
         )}

      _incomplete ->
        {:ok, redirect(socket, to: "/student")}
    end
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
    %{sender: :assistant, content: content} = List.last(messages)
    content
  end

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
    llm_tools = socket.assigns.llm_tools

    Task.start(fn ->
      retry with: constant_backoff(100) |> Stream.take(10) do
        process_llm_request(message, llm_context, live_view_pid, llm_tools)
      end
    end)

    socket
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
  end

  @spec process_llm_request(String.t(), term(), pid(), list()) :: :ok | :retry
  defp process_llm_request(message, llm_context, live_view_pid, llm_tools) do
    chat_mod = Application.get_env(:cara, :chat_module, Cara.AI.Chat)

    case chat_mod.send_message_stream(message, llm_context, tools: llm_tools) do
      {:ok, stream, llm_context_builder, tool_calls} ->
        handle_llm_stream_response(
          stream,
          llm_context,
          llm_context_builder,
          tool_calls,
          message,
          live_view_pid,
          llm_tools,
          chat_mod
        )

      {:error, reason} ->
        send(live_view_pid, {:llm_error, "Error: #{inspect(reason)}"})
        :error
    end
  rescue
    exception ->
      error_message = format_exception_message(exception)
      send(live_view_pid, {:llm_error, error_message})
      :error
  end

  @spec handle_llm_stream_response(
          Enumerable.t(),
          ReqLLM.Context.t(),
          (String.t() -> ReqLLM.Context.t()),
          list(),
          String.t(),
          pid(),
          list(),
          module()
        ) :: :ok | :retry
  defp handle_llm_stream_response(
         stream,
         llm_context,
         llm_context_builder,
         tool_calls,
         message,
         live_view_pid,
         llm_tools,
         chat_mod
       ) do
    if Enum.empty?(tool_calls) do
      # No tool calls, process the stream normally
      if process_stream(stream, live_view_pid, llm_context_builder) do
        :ok
      else
        send(live_view_pid, {:llm_error, "The AI did not return a response. Please try again."})
        :error
      end
    else
      # Tool calls found - use ToolHandler to process them!
      # This is now a pure function call - easy to test!
      llm_context_with_assistant_tool_calls =
        Context.append(llm_context, Context.assistant("", tool_calls: tool_calls))

      # Execute tools and get updated context - all in one pure function!
      updated_llm_context =
        ToolHandler.handle_tool_calls(
          tool_calls,
          llm_context_with_assistant_tool_calls,
          llm_tools,
          chat_mod
        )

      # Make another LLM call with the tool results
      process_llm_request(message, updated_llm_context, live_view_pid, llm_tools)
    end
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
  defp format_exception_message(%{
         __struct__: ReqLLM.Error.API.Request,
         status: 429,
         response_body: response_body
       }) do
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

  ## Rendering Helpers

  @doc """
  Renders markdown content as safe HTML.

  This is primarily used in templates to render chat message content.
  """
  @spec render_markdown(String.t()) :: Phoenix.HTML.safe()
  def render_markdown(content) do
    MDEx.new(markdown: content)
    |> MDExGFM.attach()
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end

  @spec app_version() :: String.t()
  defp app_version do
    Application.spec(:cara, :vsn) |> to_string
  end
end
