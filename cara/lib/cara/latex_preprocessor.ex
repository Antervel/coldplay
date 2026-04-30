defmodule Cara.LaTeXPreprocessor do
  @moduledoc """
  A pre-processing step to run on Markdown text before passing it to MDEx,
  so that LaTeX expressions not wrapped in $ or $$ get wrapped automatically.

  It also protects Mermaid blocks from these substitutions.
  """

  # ---- delimiter-based patterns ------------------------------------------------

  @display_math_re ~r/\\\[(.+?)\\\]/s
  @inline_math_re ~r/\\\((.+?)\\\)/s

  # ---- known math command names ------------------------------------------------

  @math_commands ~w(
    alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa
    lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi
    psi omega
    Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega
    int oint iint iiint sum prod coprod lim limsup liminf inf sup max min
    frac dfrac tfrac cfrac sqrt partial nabla
    left right middle big Big bigg Bigg
    mathbb mathbf mathcal mathscr mathrm mathit mathsf mathtt
    text textrm
    cdot cdots ldots vdots ddots times div pm mp
    leq geq neq approx equiv sim simeq cong propto
    rightarrow leftarrow Rightarrow Leftarrow leftrightarrow Leftrightarrow
    uparrow downarrow to gets mapsto
    forall exists in notin subset supset subseteq supseteq cup cap
    infty emptyset Re Im
    sin cos tan cot sec csc arcsin arccos arctan
    log ln exp det tr ker dim deg
  )

  @cmd_alternation Enum.join(@math_commands, "|")

  # ---- bracket/paren heuristic patterns ---------------------------------------

  @bare_bracket_re Regex.compile!(
                     "(?<!\\[)" <>
                       "\\[" <>
                       "\\s*" <>
                       "(\\\\(?:#{@cmd_alternation})[\\s\\S]*?)" <>
                       "\\s*" <>
                       "\\]" <>
                       "(?!\\()",
                     [:dotall]
                   )

  @bare_paren_re Regex.compile!(
                   "(?<![\\\\(])" <>
                     "\\(" <>
                     "\\s*" <>
                     "(\\\\(?:#{@cmd_alternation})[\\s\\S]*?)" <>
                     "\\s*" <>
                     "\\)",
                   [:dotall]
                 )

  # ---- public API -------------------------------------------------------------

  def run(text) do
    # Protect mermaid and other code blocks
    # We use a split that includes the matched blocks
    parts = String.split(text, ~r/(```[\s\S]*?```)/, include_captures: true)

    parts
    |> Enum.map(fn part ->
      if String.starts_with?(part, "```") do
        # Inside code block, return as is
        part
      else
        # Outside code blocks
        process_text(part)
      end
    end)
    |> Enum.join("")
  end

  defp process_text(text) do
    text
    |> convert_display_brackets()
    |> convert_inline_parens()
    |> convert_bare_brackets()
    |> convert_bare_parens()
  end

  # ---- private helpers --------------------------------------------------------

  defp convert_display_brackets(text) do
    Regex.replace(@display_math_re, text, fn _, inner -> "$$#{inner}$$" end)
  end

  defp convert_inline_parens(text) do
    Regex.replace(@inline_math_re, text, fn _, inner -> "$#{inner}$" end)
  end

  defp convert_bare_brackets(text) do
    Regex.replace(@bare_bracket_re, text, fn _, inner -> "$$#{String.trim(inner)}$$" end)
  end

  defp convert_bare_parens(text) do
    Regex.replace(@bare_paren_re, text, fn _, inner -> "$#{String.trim(inner)}$" end)
  end
end
