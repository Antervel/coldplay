defmodule Cara.AI.Prompt do
  @moduledoc """
  Domain-agnostic template renderer for AI prompts.

  This module provides generic template rendering utilities that know nothing
  about any specific domain (e.g., education). Domain-specific prompts should
  live in their own modules (e.g., `Cara.Education.Prompts`).

  ## Examples

      iex> Cara.AI.Prompt.render("my_template", %{name: "Alice"})

  """

  @doc """
  Renders a specific template by name.

  The template file should exist in the prompts directory as `<template_name>.eex`.
  The `assigns` map keys are converted to a keyword list for EEx evaluation.
  """
  def render(template_name, assigns) do
    prompt_dir()
    |> Path.join("#{template_name}.eex")
    |> File.read!()
    |> EEx.eval_string(assigns: Map.to_list(assigns))
  end

  defp prompt_dir do
    Path.join(:code.priv_dir(:cara), "prompts")
  end
end
