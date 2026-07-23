defmodule CaraWeb.MarkdownHelpers do
  @moduledoc """
  Helpers for rendering markdown with support for LaTeX (KaTeX) and Mermaid.
  """
  import Phoenix.HTML

  @doc """
  Renders markdown content as safe HTML.

  This is primarily used in templates to render chat message content.
  """
  @spec render_markdown(String.t(), String.t() | nil, keyword()) :: Phoenix.HTML.safe()
  def render_markdown(content, prefix \\ nil, opts \\ []) do
    sanitize = Keyword.get(opts, :sanitize, false)

    content =
      content
      |> Cara.LaTeXPreprocessor.run()
      |> fix_mermaid_labels()

    doc = MDEx.new(markdown: content, extension: [math_dollars: true])

    processed_doc =
      doc
      |> MDExGFM.attach()
      |> MDExMermaid.attach(
        # already initialized in app.js
        mermaid_init: "",
        mermaid_pre_attrs: fn seq ->
          id = if prefix, do: "mermaid-#{prefix}-#{seq}", else: "mermaid-#{seq}"
          ~s(id="#{id}" class="mermaid" phx-hook="MermaidHook")
        end
      )
      |> rename_steps("mermaid")
      |> MDExKatex.attach(
        # already initialized
        katex_init: "",
        katex_block_attrs: fn seq ->
          id = if prefix, do: "katex-#{prefix}-#{seq}", else: "katex-#{seq}"
          ~s(id="#{id}" class="katex-block" phx-hook="KatexHook")
        end,
        katex_inline_attrs: fn seq ->
          id = if prefix, do: "katex-inline-#{prefix}-#{seq}", else: "katex-inline-#{seq}"
          ~s(id="#{id}" class="katex-inline" phx-hook="KatexHook")
        end
      )
      |> rename_steps("katex")

    processed_doc
    |> then(fn doc ->
      if sanitize do
        MDEx.to_html!(doc, sanitize: MDEx.Document.default_sanitize_options())
      else
        MDEx.to_html!(doc)
      end
    end)
    # credo:disable-for-next-line
    |> raw()
  end

  defp fix_mermaid_labels(content) do
    # Regex to find mermaid blocks
    Regex.replace(~r/```mermaid\n([\s\S]+?)\n```/, content, fn _, code ->
      fixed_code = fix_mermaid_edge_labels(code)
      "```mermaid\n#{fixed_code}\n```"
    end)
  end

  defp fix_mermaid_edge_labels(code) do
    Regex.replace(~r/(\|)([^"\n\|]+?)(\|)/, code, fn _, pipe1, label, pipe2 ->
      if should_quote_mermaid_label?(label) do
        "#{pipe1}\"#{label}\"#{pipe2}"
      else
        "#{pipe1}#{label}#{pipe2}"
      end
    end)
  end

  defp should_quote_mermaid_label?(label) do
    String.contains?(label, ["(", ")"]) or Regex.run(~r/[^\x00-\x7F]/, label)
  end

  defp rename_steps(doc, suffix) do
    # Rename only known colliding steps to avoid interfering with core MDEx steps
    # or steps from other plugins that don't collide.
    colliding_steps = [:update_code_blocks, :inject_init, :enable_unsafe]

    new_steps =
      Enum.map(doc.steps, fn {key, fun} ->
        if key in colliding_steps do
          {String.to_atom("#{key}_#{suffix}"), fun}
        else
          {key, fun}
        end
      end)

    new_current_steps =
      Enum.map(doc.current_steps, fn key ->
        if key in colliding_steps do
          String.to_atom("#{key}_#{suffix}")
        else
          key
        end
      end)

    %{doc | steps: new_steps, current_steps: new_current_steps}
  end
end
