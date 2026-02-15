defmodule Cara.AI.Tools.WikipediaTest do
  use ExUnit.Case
  import Mox

  alias Cara.AI.Tools.Wikipedia

  setup :verify_on_exit!

  setup do
    # Configure Cara.Wikipedia to use our mock HTTP client
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
    :ok
  end

  # Tests for wikipedia_search/0
  test "wikipedia_search/0 returns a tool definition" do
    tool = Wikipedia.wikipedia_search()
    assert tool.name == "wikipedia_search"
    assert is_function(tool.callback, 1)
    assert tool.parameter_schema |> Keyword.get(:query) |> Keyword.get(:type) == :string
    assert tool.parameter_schema |> Keyword.get(:query) |> Keyword.get(:required) == true
  end

  test "wikipedia_search/0 callback returns search results on success" do
    mock_response = [
      "search",
      ["Elixir (programming language)"],
      ["Elixir is a functional, concurrent, general-purpose programming language..."],
      ["https://en.wikipedia.org/wiki/Elixir_(programming_language)"]
    ]

    expect(Cara.HTTPClientMock, :get, fn url, opts ->
      assert url == "https://en.wikipedia.org/w/api.php"
      assert opts[:params][:search] == "Elixir"
      {:ok, %{status: 200, body: mock_response}}
    end)

    tool = Wikipedia.wikipedia_search()
    {:ok, results} = tool.callback.(%{"query" => "Elixir"})

    assert results ==
             "Wikipedia search results for 'Elixir':\n1. Elixir (programming language) - https://en.wikipedia.org/wiki/Elixir_(programming_language)"
  end

  test "wikipedia_search/0 callback handles empty search results" do
    mock_response = [
      "search",
      [],
      [],
      []
    ]

    expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: mock_response}}
    end)

    tool = Wikipedia.wikipedia_search()
    {:ok, results} = tool.callback.(%{"query" => "nonexistent"})
    assert results == "No Wikipedia articles found for 'nonexistent'."
  end

  test "wikipedia_search/0 callback returns an error on Wikipedia search failure" do
    expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 500, body: "Error"}}
    end)

    tool = Wikipedia.wikipedia_search()
    {:error, reason} = tool.callback.(%{"query" => "Elixir"})
    assert reason == "Wikipedia search failed: HTTP 500"
  end

  # Tests for wikipedia_get_article/0
  test "wikipedia_get_article/0 returns a tool definition" do
    tool = Wikipedia.wikipedia_get_article()
    assert tool.name == "wikipedia_get_article"
    assert is_function(tool.callback, 1)
    assert tool.parameter_schema |> Keyword.get(:title) |> Keyword.get(:type) == :string
    assert tool.parameter_schema |> Keyword.get(:title) |> Keyword.get(:required) == true
  end

  test "wikipedia_get_article/0 callback returns full article on success" do
    summary_mock_response = %{
      "title" => "Elixir (programming language)",
      "extract" => "Elixir is a functional, concurrent, general-purpose programming language...",
      "content_urls" => %{"desktop" => %{"page" => "https://en.wikipedia.org/wiki/Elixir_(programming_language)"}},
      "originalimage" => %{
        "source" =>
          "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
      }
    }

    content_mock_response = %{
      "parse" => %{
        "title" => "Elixir (programming language)",
        "pageid" => 12_345,
        "text" => %{"*" => "<p>Full content of Elixir article...</p>"}
      }
    }

    # Expect for summary fetch
    expect(Cara.HTTPClientMock, :get, fn url, _opts ->
      assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
      {:ok, %{status: 200, body: summary_mock_response}}
    end)

    # Expect for full content fetch (using action=parse)
    expect(Cara.HTTPClientMock, :get, fn url, opts ->
      assert url == "https://en.wikipedia.org/w/api.php"
      assert opts[:params] == %{action: "parse", page: "Elixir (programming language)", format: "json"}
      {:ok, %{status: 200, body: content_mock_response}}
    end)

    tool = Wikipedia.wikipedia_get_article()
    {:ok, article} = tool.callback.(%{"title" => "Elixir (programming language)"})

    assert article ==
             "Title: Elixir (programming language)\nURL: https://en.wikipedia.org/wiki/Elixir_(programming_language)\n\nContent:\nFull content of Elixir article..."
  end

  test "wikipedia_get_article/0 callback returns an error when article is not found" do
    expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 404, body: "Not Found"}}
    end)

    tool = Wikipedia.wikipedia_get_article()
    {:error, reason} = tool.callback.(%{"title" => "NonExistentArticle"})
    assert reason == "Failed to retrieve Wikipedia article: Article not found"
  end

  test "wikipedia_get_article/0 callback returns an error on HTTP failure during summary fetch" do
    expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 500, body: "Internal Server Error"}}
    end)

    tool = Wikipedia.wikipedia_get_article()
    {:error, reason} = tool.callback.(%{"title" => "Elixir"})
    assert reason == "Failed to retrieve Wikipedia article: HTTP 500"
  end

  test "wikipedia_get_article/0 callback returns an error on HTTP failure during content fetch" do
    summary_mock_response = %{
      "title" => "Elixir (programming language)",
      "extract" => "Elixir is a functional, concurrent, general-purpose programming language...",
      "content_urls" => %{"desktop" => %{"page" => "https://en.wikipedia.org/wiki/Elixir_(programming_language)"}},
      "originalimage" => %{
        "source" =>
          "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
      }
    }

    # Expect for summary fetch
    expect(Cara.HTTPClientMock, :get, fn url, _opts ->
      assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
      {:ok, %{status: 200, body: summary_mock_response}}
    end)

    # Expect for full content fetch to fail with HTTP error
    expect(Cara.HTTPClientMock, :get, fn url, _opts ->
      assert url == "https://en.wikipedia.org/w/api.php"
      {:ok, %{status: 500, body: "Internal Server Error"}}
    end)

    tool = Wikipedia.wikipedia_get_article()
    {:error, reason} = tool.callback.(%{"title" => "Elixir (programming language)"})
    assert reason == "Failed to retrieve Wikipedia article: HTTP 500"
  end
end
