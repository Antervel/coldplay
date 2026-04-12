defmodule Cara.Education.Prompts do
  @moduledoc """
  Educational domain-specific prompt rendering.

  This module contains prompts that are specific to the educational domain,
  such as student greeting prompts. These are decoupled from the generic
  AI prompt utilities in `Cara.AI.Prompt`.

  ## Examples

      iex> Cara.Education.Prompts.render_greeting_prompt(%{name: "Alice", subject: "Math", age: "10"})
      "You are a warm, encouraging learning assistant helping Alice..."

  """

  @doc """
  Renders the system prompt for a student greeting.

  The prompt configures the AI to be a warm, encouraging learning assistant
  matched to the student's age and subject.
  """
  @spec render_greeting_prompt(map()) :: String.t()
  def render_greeting_prompt(student_info) do
    assigns = [
      name: student_info.name,
      subject: student_info.subject,
      age: student_info.age
    ]

    prompt_dir()
    |> Path.join("greeting.eex")
    |> EEx.eval_file(assigns)
  end

  defp prompt_dir do
    Path.join(:code.priv_dir(:cara), "prompts")
  end
end
