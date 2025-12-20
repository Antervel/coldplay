defmodule Cara.AI.Prompt do
  @moduledoc """
    Central module to get prompts from templates
  """
  @prompt_dir Path.join(:code.priv_dir(:cara), "prompts")

  def render(template_name, assigns) do
    @prompt_dir
    |> Path.join("#{template_name}.eex")
    |> File.read!()
    |> EEx.eval_string(assigns: Map.to_list(assigns))
  end
end
