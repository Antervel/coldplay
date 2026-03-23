defmodule Cara.AI.Prompt do
  @moduledoc """
  Central module to get prompts from templates.
  """

  defp prompt_dir do
    Path.join(:code.priv_dir(:cara), "prompts")
  end

  @doc """
  Renders the system prompt for a student.
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

  @doc """
  Renders a specific template by name.
  """
  def render(template_name, assigns) do
    prompt_dir()
    |> Path.join("#{template_name}.eex")
    |> File.read!()
    |> EEx.eval_string(assigns: Map.to_list(assigns))
  end
end
