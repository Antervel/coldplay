defmodule Cara.AI.Tools.Wikipedia do
  @moduledoc """
  A module containing tools to interact with Wikipedia.

  Example:
  iex> wikipedia_search_tool = Cara.AI.Tools.Wikipedia.wikipedia_search()                                                                                         │
  iex> wikipedia_get_article_tool = Cara.AI.Tools.Wikipedia.wikipedia_get_article()
  iex> {:ok, results} = wikipedia_search_tool.callback.(%{"query" => "Elixir programming language"})
  iex> {:ok, article} = wikipedia_get_article_tool.callback.(%{"title" => "Elixir (programming language)"})
  """
  alias Cara.Wikipedia
  alias Floki
  alias ReqLLM.Tool

  def wikipedia_search do
    Tool.new!(
      name: "wikipedia_search",
      description:
        ~s|Searches Wikipedia for articles based on a given query. Use this tool when you need to find information on a topic. Returns a list of article summaries including their titles, descriptions, and URLs. Example: {"query": "Elixir programming language"}|,
      parameter_schema: [
        query: [type: :string, required: true, doc: "The search query to find Wikipedia articles."]
      ],
      callback: fn args ->
        query = args[:query] || args["query"]

        case Wikipedia.search_articles(query) do
          {:ok, articles} ->
            if Enum.empty?(articles) do
              {:ok, "No Wikipedia articles found for '#{query}'."}
            else
              formatted_results =
                articles
                |> Enum.with_index(1)
                |> Enum.map_join("\n", fn {article, index} ->
                  "#{index}. #{to_string(article.title)} - #{to_string(article.url)}"
                end)

              {:ok, "Wikipedia search results for '#{query}':\n#{formatted_results}"}
            end

          {:error, reason} ->
            {:error, "Wikipedia search failed: #{reason}"}
        end
      end
    )
  end

  def wikipedia_get_article do
    Tool.new!(
      name: "wikipedia_get_article",
      description:
        ~s|Retrieves the full content of a Wikipedia article given its exact title. Use this tool when you need detailed information from a specific Wikipedia article. Example: {"title": "Elixir (programming language)"}|,
      parameter_schema: [
        title: [type: :string, required: true, doc: "The exact title of the Wikipedia article to retrieve."]
      ],
      callback: fn args ->
        title = args[:title] || args["title"]

        case Wikipedia.get_full_article(title) do
          {:ok, %{title: article_title, content: content, url: url}} ->
            text_content =
              case Floki.parse_fragment(content) do
                {:ok, parsed_html} -> Floki.text(parsed_html)
                # Fallback to original content if parsing fails
                {:error, _reason} -> content
              end

            formatted_article = "Title: #{article_title}\nURL: #{url}\n\nContent:\n#{text_content}"
            {:ok, formatted_article}

          {:error, reason} ->
            {:error, "Failed to retrieve Wikipedia article: #{reason}"}
        end
      end
    )
  end
end
