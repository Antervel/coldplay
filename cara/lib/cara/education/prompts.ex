defmodule Cara.Education.Prompts do
  @moduledoc """
  Educational-specific prompt logic.
  """

  alias Cara.AI.Prompt

  @doc """
  Renders the system prompt for a student.
  """
  @spec render_greeting_prompt(map()) :: String.t()
  def render_greeting_prompt(student_info) do
    assigns = %{
      name: student_info.name,
      subject: student_info.subject,
      age: student_info.age
    }

    Prompt.render("greeting", assigns)
  end
end
