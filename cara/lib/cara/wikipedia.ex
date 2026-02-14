defmodule Cara.Wikipedia do
  @moduledoc """
  A module to interface with the Wikipedia API for searching articles and retrieving full articles.
  """

  @doc """
  Searches for Wikipedia articles using a query term.

  Returns a list of article summaries with title, extract, and URL.
  """
  @spec search_articles(String.t()) :: {:ok, list()} | {:error, term()}
  def search_articles(query) do
    case Req.get(
           "https://en.wikipedia.org/w/api.php",
           query: %{
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
  end

  @doc """
  Retrieves a full Wikipedia article by title.

  Returns the article content with title, extract, and full content.
  """
  @spec get_article(String.t()) :: {:ok, map()} | {:error, term()}
  def get_article(title) do
    case Req.get(
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
  end

  @doc """
  Retrieves a full Wikipedia article with its full content.

  Returns the article content including full text.
  """
  @spec get_full_article(String.t()) :: {:ok, map()} | {:error, term()}
  def get_full_article(title) do
    case fetch_article_summary(title) do
      {:ok, summary_response} ->
        case extract_article_url(summary_response) do
          {:ok, article_url} ->
            case fetch_article_content(article_url) do
              {:ok, content_response} ->
                case parse_full_article(summary_response, content_response) do
                  {:ok, parsed_article} -> {:ok, parsed_article}
                  error -> error
                end

              error ->
                error
            end

          {:error, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  defp fetch_article_summary(title) do
    case Req.get(
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

  defp fetch_article_content(article_url) do
    case Req.get(article_url,
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
      [_, _, titles, extracts] ->
        Enum.zip(titles, extracts)
        |> Enum.map(fn {title, extract} ->
          %{
            title: title,
            extract: extract,
            url: "https://en.wikipedia.org/wiki/#{URI.encode(title)}"
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
    %{
      title: summary["title"],
      extract: summary["extract"],
      content: content["parse"]["text"]["*"],
      url: summary["content_urls"]["desktop"]["page"],
      image: summary["originalimage"]["source"]
    }
  end
end
