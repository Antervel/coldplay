defmodule Cara.Education.Session do
  @moduledoc """
  Manages the lifecycle of an educational chat session.
  """

  alias Cara.AI.BranchedChat
  alias Cara.AI.Message
  alias Cara.AI.Tools
  alias Cara.Education.Prompts, as: EducationPrompts

  # Get the chat module from config at runtime (allows switching to mock in tests)
  defp chat_module do
    Application.get_env(:cara, :chat_module, Cara.AI.Chat)
  end

  @doc """
  Initializes a new educational chat session for a student.
  """
  def init_student_session(student_info) do
    system_prompt = EducationPrompts.render_greeting_prompt(student_info)
    llm_tools = Tools.load_tools()

    initial_messages = [welcome_message_for_student(student_info)]
    initial_context = chat_module().new_context(system_prompt)

    branched_chat = BranchedChat.new(chat_module(), initial_messages, initial_context)

    {:ok,
     %{
       branched_chat: branched_chat,
       llm_tools: llm_tools
     }}
  end

  defp welcome_message_for_student(%{name: name, subject: subject}) do
    Message.new(:assistant, "Hello **#{name}**! Let's learn about #{subject} together! 🎓")
  end
end
