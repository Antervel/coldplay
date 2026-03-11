defmodule Cara.Wikipedia do
  @moduledoc """
  A module to interface with the Wikipedia API for searching articles and retrieving full articles.

  Example:

  iex(1)> Cara.Wikipedia.search_articles("elixir")
  iex(2)> Cara.Wikipedia.get_article("Elixir")
  iex(3)> Cara.Wikipedia.get_full_article("Elixir")
  """

  defp http_client do
    Application.get_env(:cara, :http_client, Req)
  end

  @doc """
  Searches for Wikipedia articles using a query term.

  Returns a list of article summaries with title, extract, and URL.
  """
  @spec search_articles(String.t()) :: {:ok, list()} | {:error, term()}
  def search_articles(query) do
    start_time = :erlang.monotonic_time(:millisecond)

    result =
      case http_client().get(
             "https://en.wikipedia.org/w/api.php",
             params: %{
               action: "opensearch",
               search: query,
               limit: 10,
               format: "json"
             },
             headers: %{
               "User-Agent" => "Cara-Educational-App/1.0"
             }
           ) do
        {:ok, response} ->
          case response.status do
            200 ->
              {:ok, parse_search_response(response.body)}

            status ->
              {:error, "HTTP #{status}"}
          end

        error ->
          {:error, error}
      end

    end_time = :erlang.monotonic_time(:millisecond)
    IO.puts("Wikipedia search_articles('#{query}') took #{end_time - start_time}ms")
    result
  end

  @doc """
  Retrieves a full Wikipedia article by title.

  Returns the article content with title, extract, and full content.
  """
  @spec get_article(String.t()) :: {:ok, map()} | {:error, term()}
  def get_article(title) do
    start_time = :erlang.monotonic_time(:millisecond)

    result =
      case http_client().get(
             "https://en.wikipedia.org/api/rest_v1/page/summary/#{URI.encode(title)}",
             headers: %{
               "User-Agent" => "Cara-Educational-App/1.0"
             }
           ) do
        {:ok, response} ->
          case response.status do
            200 ->
              {:ok, parse_article_response(response.body)}

            404 ->
              {:error, "Article not found"}

            status ->
              {:error, "HTTP #{status}"}
          end

        error ->
          {:error, error}
      end

    end_time = :erlang.monotonic_time(:millisecond)
    IO.puts("Wikipedia get_article('#{title}') took #{end_time - start_time}ms")
    result
  end

  @doc """
  Retrieves a full Wikipedia article with its full content.

  Returns the article content including full text.
  """
  @spec get_full_article(String.t()) :: {:ok, map()} | {:error, term()}
  def get_full_article(title) do
    start_time = :erlang.monotonic_time(:millisecond)

    result =
      with {:ok, summary_response} <- fetch_article_summary(title),
           {:ok, _article_url} <- extract_article_url(summary_response),
           {:ok, content_response} <- fetch_article_content(title),
           {:ok, parsed_article} <- parse_full_article(summary_response, content_response) do
        {:ok, parsed_article}
      else
        error -> error
      end

    end_time = :erlang.monotonic_time(:millisecond)
    IO.puts("Wikipedia get_full_article('#{title}') took #{end_time - start_time}ms")
    result
  end

  defp fetch_article_summary(title) do
    case http_client().get(
           "https://en.wikipedia.org/api/rest_v1/page/summary/#{URI.encode(title)}",
           headers: %{
             "User-Agent" => "Cara-Educational-App/1.0"
           }
         ) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end

  defp extract_article_url(summary_response) do
    case summary_response.status do
      200 ->
        case Map.get(summary_response.body, "content_urls", %{}) do
          %{"desktop" => %{"page" => article_url}} when not is_nil(article_url) ->
            {:ok, article_url}

          _ ->
            {:error, "Could not fetch article URL"}
        end

      404 ->
        {:error, "Article not found"}

      status ->
        {:error, "HTTP #{status}"}
    end
  end

  defp fetch_article_content(title) do
    case http_client().get(
           "https://en.wikipedia.org/w/api.php",
           params: %{
             action: "query",
             prop: "extracts",
             titles: title,
             explaintext: 1,
             exsectionformat: "plain",
             format: "json",
             formatversion: 2
           },
           headers: %{
             "User-Agent" => "Cara-Educational-App/1.0"
           }
         ) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end

  defp parse_full_article(summary_response, content_response) do
    case content_response.status do
      200 ->
        {:ok, parse_full_article_response(summary_response.body, content_response.body)}

      status ->
        {:error, "HTTP #{status}"}
    end
  end

  defp parse_search_response(response) do
    case response do
      [_search_term, titles, extracts, urls] ->
        Enum.zip(titles, extracts)
        |> Enum.zip(urls)
        |> Enum.map(fn {{title, extract}, url} ->
          %{
            title: title,
            extract: extract,
            url: url
          }
        end)

      _ ->
        []
    end
  end

  defp parse_article_response(body) do
    %{
      title: body["title"],
      extract: body["extract"],
      url: body["content_urls"]["desktop"]["page"],
      image: body["originalimage"]["source"]
    }
  end

  defp parse_full_article_response(summary, content) do
    # Extract plain text content from the 'content' response
    plain_text_content =
      content
      |> Map.get("query")
      |> Map.get("pages")
      |> hd()
      |> Map.get("extract")

    %{
      title: summary["title"],
      extract: summary["extract"],
      content: plain_text_content,
      url: summary["content_urls"]["desktop"]["page"],
      image: summary["originalimage"]["source"]
    }
  end
end
