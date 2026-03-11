defmodule Cara.AI.Tools.Wikipedia do
  @moduledoc """
  A module containing tools to interact with Wikipedia.

  Example:
  iex> wikipedia_search_tool = Cara.AI.Tools.Wikipedia.wikipedia_search()
  iex> wikipedia_get_article_tool = Cara.AI.Tools.Wikipedia.wikipedia_get_article()
  iex> {:ok, results} = wikipedia_search_tool.callback.(%{"query" => "Elixir programming language"})
  iex> {:ok, article} = wikipedia_get_article_tool.callback.(%{"title" => "Elixir (programming language)"})
  """
  alias Cara.Wikipedia
  alias ReqLLM.Tool

  def wikipedia_search do
    Tool.new!(
      name: "wikipedia_search",
      description: "Search Wikipedia. Input: {\"query\": \"topic\"}",
      parameter_schema: [
        query: [type: :string, required: true, doc: "The search query"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)
        query = args[:query] || args["query"]

        result =
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

        end_time = :erlang.monotonic_time(:millisecond)
        IO.puts("Tool 'wikipedia_search' total execution took #{end_time - start_time}ms")
        result
      end
    )
  end

  def wikipedia_get_article do
    Tool.new!(
      name: "wikipedia_get_article",
      description: "Get full Wikipedia article. Input: {\"title\": \"Exact Title\"}",
      parameter_schema: [
        title: [type: :string, required: true, doc: "The exact title"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)
        title = args[:title] || args["query"] || args["title"]

        result =
          case Wikipedia.get_full_article(title) do
            {:ok, %{title: article_title, content: content, url: url}} ->
              formatted_article = "Title: #{article_title}\nURL: #{url}\n\nContent:\n#{content}"
              {:ok, formatted_article}

            {:error, reason} ->
              {:error, "Failed to retrieve Wikipedia article: #{reason}"}
          end

        end_time = :erlang.monotonic_time(:millisecond)
        IO.puts("Tool 'wikipedia_get_article' total execution took #{end_time - start_time}ms")
        result
      end
    )
  end
end
