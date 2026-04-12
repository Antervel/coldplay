defmodule Cara.Education.Session do
  @moduledoc """
  Manages educational chat session initialization and state.

  This module encapsulates the domain logic for setting up a student's chat
  session, including generating welcome messages, building the initial LLM
  context, and creating the branched chat structure. It is decoupled from
  the web interface (LiveView).

  ## Usage

      session = Session.new(student_info, chat_module)
      {:ok, session} = Session.subscribe_and_broadcast(session, chat_id, socket)

  """

  alias BranchedLLM.BranchedChat
  alias BranchedLLM.Message
  alias Cara.AI.Tools
  alias Cara.Education.Monitoring
  alias Cara.Education.Prompts

  @type student_info :: %{
          name: String.t(),
          subject: String.t(),
          age: String.t(),
          chat_id: String.t()
        }

  @type t :: %__MODULE__{
          student_info: student_info(),
          branched_chat: BranchedChat.t(),
          llm_tools: [ReqLLM.Tool.t()],
          tool_usage_counts: map(),
          bubble_width: String.t()
        }

  defstruct [
    :student_info,
    :branched_chat,
    :llm_tools,
    :tool_usage_counts,
    :bubble_width
  ]

  @doc """
  Creates a new educational session for a student.

  ## Parameters

    * `student_info` - Map with `name`, `subject`, `age`, and `chat_id`
    * `chat_module` - The AI chat module to use (e.g., `Cara.AI.Chat`)
    * `ui_config` - Optional map of UI configuration (defaults to app config)

  """
  @spec new(student_info(), module(), map() | nil) :: t()
  def new(student_info, chat_module, ui_config \\ nil) do
    ui_config = ui_config || Application.get_env(:cara, :ui, %{})
    bubble_width = Map.get(ui_config, :bubble_width, "40%")

    system_prompt = Prompts.render_greeting_prompt(student_info)
    llm_tools = Tools.load_tools()

    initial_messages = [welcome_message_for_student(student_info)]
    initial_context = chat_module.new_context(system_prompt)

    branched_chat = BranchedChat.new(chat_module, initial_messages, initial_context)

    tool_usage_counts =
      Enum.reduce(llm_tools, %{}, fn tool, acc ->
        Map.put(acc, tool.name, 0)
      end)

    %__MODULE__{
      student_info: student_info,
      branched_chat: branched_chat,
      llm_tools: llm_tools,
      tool_usage_counts: tool_usage_counts,
      bubble_width: bubble_width
    }
  end

  @doc """
  Creates a new session, subscribes/broadcasts (if connected), and assigns all state to the socket.

  This is the primary entry point for mounting a new educational chat session.
  """
  @spec assign_new_session(Phoenix.LiveView.Socket.t(), student_info(), module()) ::
          Phoenix.LiveView.Socket.t()
  def assign_new_session(socket, student_info, chat_module) do
    session = new(student_info, chat_module)
    do_subscribe_and_broadcast(session, socket)
    assign_to_socket(socket, session)
  end

  defp do_subscribe_and_broadcast(%__MODULE__{} = session, socket) do
    if connected?(socket) and Monitoring.monitoring_enabled?() do
      Monitoring.subscribe()
      Monitoring.broadcast_chat_started(socket, session.student_info)
    end

    :ok
  end

  @doc """
  Assigns the session state onto the LiveView socket.
  """
  @spec assign_to_socket(Phoenix.LiveView.Socket.t(), t()) :: Phoenix.LiveView.Socket.t()
  def assign_to_socket(socket, %__MODULE__{} = session) do
    Phoenix.Component.assign(socket,
      branched_chat: session.branched_chat,
      show_branches: false,
      message_data: %{"message" => ""},
      student_info: session.student_info,
      llm_tools: session.llm_tools,
      bubble_width: session.bubble_width,
      tool_usage_counts: session.tool_usage_counts,
      show_notes: false,
      notes: "",
      show_sidebar: false,
      chat_id: session.student_info.chat_id
    )
  end

  @doc """
  Broadcasts that the student has left the chat.
  """
  @spec broadcast_left(Phoenix.LiveView.Socket.t(), String.t()) :: :ok
  def broadcast_left(socket, chat_id) do
    if Map.has_key?(socket.assigns, :chat_id) and Monitoring.monitoring_enabled?() do
      Monitoring.broadcast_chat_left(socket, chat_id)
    end

    :ok
  end

  defp connected?(socket), do: Phoenix.LiveView.connected?(socket)

  defp welcome_message_for_student(%{name: name, subject: subject}) do
    Message.new(:assistant, "Hello **#{name}**! Let's learn about #{subject} together! 🎓")
  end
end
