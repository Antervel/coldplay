defmodule CaraWeb.ChatLive do
  use CaraWeb, :live_view
  use Retry
  require Logger
  alias Cara.AI.ToolHandler

  alias Cara.AI.Tools
  alias ReqLLM.Context

  @type chat_message :: %{sender: :user | :assistant, content: String.t()}
  @type message_data :: %{String.t() => String.t()}
  @type llm_call_params :: %{
          message: String.t(),
          llm_context: ReqLLM.Context.t(),
          live_view_pid: pid(),
          llm_tools: list(),
          chat_mod: module(),
          tool_usage_counts: map()
        }

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
        llm_tools = Tools.load_tools()

        {:ok,
         assign(socket,
           chat_messages: [welcome_message_for_student(info)],
           llm_context: chat_module().new_context(system_prompt),
           message_data: %{"message" => ""},
           app_version: app_version(),
           student_info: info,
           llm_tools: llm_tools,
           tool_status: nil,
           tool_usage_counts:
             Enum.reduce(llm_tools, %{}, fn tool, acc ->
               Map.put(acc, tool.name, 0)
             end)
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
    {:noreply, assign(socket, chat_messages: updated_messages, tool_status: nil)}
  end

  # Handle end of LLM stream
  @impl true
  def handle_info({:llm_end, llm_context_builder}, socket) when is_function(llm_context_builder, 1) do
    final_content = get_last_assistant_message_content(socket.assigns.chat_messages)
    updated_llm_context = llm_context_builder.(final_content)
    {:noreply, assign(socket, llm_context: updated_llm_context, tool_status: nil)}
  end

  @impl true
  def handle_info({:llm_status, status}, socket) do
    {:noreply, assign(socket, tool_status: status)}
  end

  @impl true
  def handle_info({:update_tool_usage_counts, tool_usage_counts}, socket) do
    {:noreply, assign(socket, :tool_usage_counts, tool_usage_counts)}
  end

  # Handle LLM errors
  @impl true
  def handle_info({:llm_error, error_message}, socket) when is_binary(error_message) do
    error_message_obj = %{sender: :assistant, content: error_message}
    {:noreply, assign(socket, chat_messages: socket.assigns.chat_messages ++ [error_message_obj], tool_status: nil)}
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
      |> assign(tool_status: "Thinking...")
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
    chat_mod = Application.get_env(:cara, :chat_module, Cara.AI.Chat)

    llm_call_params = %{
      message: message,
      llm_context: llm_context,
      live_view_pid: live_view_pid,
      llm_tools: llm_tools,
      chat_mod: chat_mod,
      tool_usage_counts: socket.assigns.tool_usage_counts
    }

    Task.start(fn ->
      retry with: constant_backoff(100) |> Stream.take(10) do
        process_llm_request(llm_call_params)
      end
    end)

    socket
  end

  @spec reset_message_form(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_message_form(socket) do
    assign(socket, message_data: %{"message" => ""})
  end

  @spec process_llm_request(llm_call_params()) :: :ok | :retry
  defp process_llm_request(
         %{
           message: message,
           llm_context: llm_context,
           live_view_pid: live_view_pid,
           llm_tools: llm_tools,
           chat_mod: chat_mod,
           tool_usage_counts: _tool_usage_counts
         } = llm_call_params
       ) do
    case chat_mod.send_message_stream(message, llm_context, tools: llm_tools) do
      {:ok, %ReqLLM.StreamResponse{} = stream_response, llm_context_builder, tool_calls} ->
        handle_llm_stream_response(
          stream_response,
          llm_context_builder,
          tool_calls,
          llm_call_params
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
          ReqLLM.StreamResponse.t(),
          (String.t() -> ReqLLM.Context.t()),
          list(),
          llm_call_params()
        ) :: :ok | :retry
  defp handle_llm_stream_response(
         stream_response,
         llm_context_builder,
         tool_calls,
         %{
           message: _message,
           llm_context: _llm_context,
           live_view_pid: live_view_pid,
           llm_tools: _llm_tools,
           chat_mod: _chat_mod,
           tool_usage_counts: tool_usage_counts
         } = llm_call_params
       ) do
    if Enum.empty?(tool_calls) do
      # No tool calls, process the stream normally
      if process_stream(stream_response, live_view_pid, llm_context_builder, tool_usage_counts) do
        :ok
      else
        send(live_view_pid, {:llm_error, "The AI did not return a response. Please try again."})
        :error
      end
    else
      # Tool calls found, execute them and recursively call LLM with results
      # We update the context in llm_call_params to include the user message
      # which is already present in the stream_response.context
      updated_llm_call_params = %{llm_call_params | llm_context: stream_response.context}
      next_llm_call_params = handle_tool_call_execution(tool_calls, updated_llm_call_params)
      process_llm_request(%{next_llm_call_params | message: ""})
    end
  end

  @spec handle_tool_call_execution(list(), llm_call_params()) :: llm_call_params()
  defp handle_tool_call_execution(
         tool_calls,
         %{
           llm_context: llm_context,
           llm_tools: llm_tools,
           chat_mod: chat_mod,
           tool_usage_counts: tool_usage_counts,
           live_view_pid: live_view_pid
         } = llm_call_params
       ) do
    tool_names = Enum.map_join(tool_calls, ", ", &ReqLLM.ToolCall.name/1)
    send(live_view_pid, {:llm_status, "Using #{tool_names}..."})

    {tool_calls_to_execute, tool_results_for_limited_tools, new_tool_usage_counts} =
      Enum.reduce(tool_calls, {[], [], tool_usage_counts}, fn tool_call, {exec_acc, limited_acc, counts_acc} ->
        tool_name = ReqLLM.ToolCall.name(tool_call)
        tool_name_atom = String.to_atom(tool_name)
        current_count = Map.get(counts_acc, tool_name_atom, 0)

        if current_count < 10 do
          {[tool_call | exec_acc], limited_acc, Map.put(counts_acc, tool_name_atom, current_count + 1)}
        else
          tool_result = Context.tool_result(tool_call.id, "Tool limit reached. Summarize with what you have")
          {exec_acc, [tool_result | limited_acc], counts_acc}
        end
      end)

    tool_calls_to_execute = Enum.reverse(tool_calls_to_execute)
    tool_results_for_limited_tools = Enum.reverse(tool_results_for_limited_tools)

    llm_context_after_tool_handling =
      if Enum.empty?(tool_calls_to_execute) do
        # If no tools are executed, just append the original tool calls to the context
        Context.append(llm_context, Context.assistant("", tool_calls: tool_calls))
      else
        # Execute allowed tools and get updated context
        llm_context_with_assistant_tool_calls =
          Context.append(llm_context, Context.assistant("", tool_calls: tool_calls_to_execute))

        ToolHandler.handle_tool_calls(
          tool_calls_to_execute,
          llm_context_with_assistant_tool_calls,
          llm_tools,
          chat_mod
        )
      end

    updated_llm_context =
      Enum.reduce(tool_results_for_limited_tools, llm_context_after_tool_handling, fn tr, acc ->
        Context.append(acc, tr)
      end)

    %{llm_call_params | llm_context: updated_llm_context, tool_usage_counts: new_tool_usage_counts}
  end

  @spec process_stream(
          ReqLLM.StreamResponse.t(),
          pid(),
          (String.t() -> ReqLLM.Context.t()),
          map()
        ) :: boolean()
  defp process_stream(stream_response, live_view_pid, llm_context_builder, tool_usage_counts) do
    send(live_view_pid, {:update_tool_usage_counts, tool_usage_counts})

    start_time = :erlang.monotonic_time(:millisecond)

    sent_any_chunks =
      stream_response
      |> ReqLLM.StreamResponse.tokens()
      |> Enum.reduce_while(false, fn chunk, _acc ->
        send(live_view_pid, {:llm_chunk, chunk})
        {:cont, true}
      end)

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("LLM streaming of answer took #{end_time - start_time}ms")

    metadata = Task.await(stream_response.metadata_task)
    Logger.info("LLM stream complete metadata: #{inspect(metadata)}")

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
