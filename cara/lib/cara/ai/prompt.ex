defmodule Cara.AI.Prompt do
  @moduledoc """
  Generic template renderer for AI prompts.
  """

  defp prompt_dir do
    Path.join(:code.priv_dir(:cara), "prompts")
  end

  @doc """
  Renders a specific template by name.
  """
  def render(template_name, assigns) when is_map(assigns) do
    render(template_name, Map.to_list(assigns))
  end

  def render(template_name, assigns) when is_list(assigns) do
    # Pass assigns as the third argument to support <%= name %>
    # AND include :assigns in that list to support <%= @name %>
    full_assigns = [{:assigns, Map.new(assigns)} | assigns]

    prompt_dir()
    |> Path.join("#{template_name}.eex")
    |> EEx.eval_file(full_assigns)
  end
end
