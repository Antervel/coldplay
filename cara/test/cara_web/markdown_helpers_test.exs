defmodule CaraWeb.MarkdownHelpersTest do
  use ExUnit.Case
  alias CaraWeb.MarkdownHelpers

  defp safe_to_string({:safe, str}), do: str
  defp safe_to_string(str), do: str

  describe "render_markdown/1" do
    test "renders plain text" do
      result = safe_to_string(MarkdownHelpers.render_markdown("Hello, world!"))
      assert byte_size(result) > 0
      assert String.contains?(result, "Hello, world!")
    end

    test "renders bold text" do
      result = safe_to_string(MarkdownHelpers.render_markdown("**bold**"))
      assert String.contains?(result, "bold")
      assert String.contains?(result, "<strong>")
    end

    test "renders italic text" do
      result = safe_to_string(MarkdownHelpers.render_markdown("*italic*"))
      assert String.contains?(result, "italic")
      assert String.contains?(result, "<em>")
    end

    test "renders headers" do
      result = safe_to_string(MarkdownHelpers.render_markdown("# Header 1"))
      assert String.contains?(result, "Header 1")
      assert String.contains?(result, "<h1")
    end

    test "renders lists" do
      result = safe_to_string(MarkdownHelpers.render_markdown("- item 1\n- item 2"))
      assert String.contains?(result, "item 1")
      assert String.contains?(result, "item 2")
      assert String.contains?(result, "<ul")
    end

    test "renders links" do
      result = safe_to_string(MarkdownHelpers.render_markdown("[link](http://example.com)"))
      assert String.contains?(result, "link")
      assert String.contains?(result, "http://example.com")
      assert String.contains?(result, "<a")
    end

    test "renders images" do
      result = safe_to_string(MarkdownHelpers.render_markdown("![alt](http://example.com/image.png)"))
      assert String.contains?(result, "alt")
      assert String.contains?(result, "http://example.com/image.png")
      assert String.contains?(result, "<img")
    end

    test "renders blockquotes" do
      result = safe_to_string(MarkdownHelpers.render_markdown("> quote"))
      assert String.contains?(result, "quote")
      assert String.contains?(result, "<blockquote")
    end

    test "renders horizontal rule" do
      result = safe_to_string(MarkdownHelpers.render_markdown("---"))
      assert String.contains?(result, "<hr")
    end

    test "renders code blocks" do
      result = safe_to_string(MarkdownHelpers.render_markdown("```\ncode\n```"))
      assert String.contains?(result, "code")
      assert String.contains?(result, "<pre")
    end

    test "renders inline code" do
      result = safe_to_string(MarkdownHelpers.render_markdown("`inline code`"))
      assert String.contains?(result, "inline code")
      assert String.contains?(result, "<code")
    end
  end

  describe "render_markdown/2 with prefix" do
    test "uses prefix for mermaid diagrams" do
      content = "```mermaid\ngraph TD\nA-->B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, "test-prefix"))
      assert String.contains?(result, "mermaid-test-prefix")
    end

    test "uses prefix for katex block" do
      content = "$$x = 1$$"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, "test-prefix"))
      assert String.contains?(result, "katex-block")
      assert String.contains?(result, "test-prefix")
    end

    test "uses prefix for katex inline" do
      content = "$x = 1$"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, "test-prefix"))
      assert String.contains?(result, "katex-inline-test-prefix")
    end

    test "uses default prefix when nil" do
      content = "```mermaid\ngraph TD\nA-->B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, nil))
      assert String.contains?(result, "mermaid-1")
    end
  end

  describe "render_markdown/3 with options" do
    test "sanitizes HTML when sanitize: true" do
      content = "<script>alert('xss')</script>"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, nil, sanitize: true))
      refute String.contains?(result, "<script>")
    end

    test "does not sanitize HTML by default" do
      content = "<strong>bold</strong>"
      result = safe_to_string(MarkdownHelpers.render_markdown(content, nil, sanitize: false))
      assert String.contains?(result, "<strong>")
    end
  end

  describe "fix_mermaid_labels/1" do
    test "quotes labels containing parentheses" do
      content = "```mermaid\ngraph TD\nA[Start (begin)]-->B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "Start (begin)")
    end

    test "quotes labels containing non-ASCII characters" do
      content = "```mermaid\ngraph TD\nA[日本語]-->B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "日本語")
    end

    test "does not quote simple labels" do
      content = "```mermaid\ngraph TD\nA[Start]-->B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "Start")
    end

    test "quotes edge labels with pipes containing parentheses" do
      content = "```mermaid\ngraph LR\nA-->|text (with parens)|B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "text (with parens)")
    end

    test "quotes edge labels with pipes containing non-ASCII" do
      content = "```mermaid\ngraph LR\nA-->|日本語|B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "日本語")
    end

    test "does not quote simple edge labels with pipes" do
      content = "```mermaid\ngraph LR\nA-->|simple|B\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "simple")
    end
  end

  describe "LaTeX preprocessing" do
    test "processes LaTeX content" do
      content = "$$\\frac{1}{2}$$"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "katex-block")
    end

    test "processes inline LaTeX" do
      content = "This is $x^2$ inline."
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "katex-inline")
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      result = safe_to_string(MarkdownHelpers.render_markdown(""))
      assert result == ""
    end

    test "handles whitespace only" do
      result = safe_to_string(MarkdownHelpers.render_markdown("   \n\n  "))
      assert result == ""
    end

    test "handles multiple paragraphs" do
      result = safe_to_string(MarkdownHelpers.render_markdown("First paragraph.\n\nSecond paragraph."))
      assert String.contains?(result, "First paragraph")
      assert String.contains?(result, "Second paragraph")
    end

    test "handles complex nested markdown" do
      content = "# Title\n\nSome **bold** and *italic* text.\n\n- List item 1\n- List item 2\n\n```\ncode here\n```"
      result = safe_to_string(MarkdownHelpers.render_markdown(content))
      assert String.contains?(result, "Title")
      assert String.contains?(result, "bold")
      assert String.contains?(result, "italic")
      assert String.contains?(result, "List item 1")
      assert String.contains?(result, "List item 2")
      assert String.contains?(result, "code here")
    end
  end

  describe "rename_steps collision avoidance" do
    test "mermaid and katex coexist without step name collisions" do
      content = """
      ```mermaid
      graph TD
      A-->B
      ```

      $$x = y$$

      $x^2$
      """

      result = safe_to_string(MarkdownHelpers.render_markdown(content, "test-prefix"))
      assert String.contains?(result, "mermaid-test-prefix")
      assert String.contains?(result, "katex-test-prefix")
      assert String.contains?(result, "katex-inline-test-prefix")
    end

    test "mermaid and katex coexist without prefix" do
      content = """
      ```mermaid
      graph TD
      A-->B
      ```

      $$x^2 + y^2 = z^2$$
      """

      result = safe_to_string(MarkdownHelpers.render_markdown(content, nil))
      assert String.contains?(result, "mermaid-1")
      assert String.contains?(result, "katex-1")
    end
  end
end
