defmodule Cara.WikipediaTest do
  use ExUnit.Case

  import Mox

  alias Cara.Wikipedia

  setup :verify_on_exit!

  setup do
    # Configure Cara.Wikipedia to use our mock HTTP client
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
    :ok
  end

  describe "search_articles/1" do
    test "returns a list of articles on success" do
      mock_response = %{
        "query" => "elixir",
        "results" => [
          %{"rank" => 1, "title" => "Elixir (programming language)\n", "score" => 0.95},
          %{"rank" => 2, "title" => "Erlang\n", "score" => 0.85}
        ],
        "elapsed_ms" => 34.6
      }

      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "http://localhost:8001/search"
        assert opts[:params] == %{q: "elixir", k: 5}

        {:ok, %{status: 200, body: mock_response}}
      end)

      {:ok, articles} = Wikipedia.search_articles("elixir")

      assert articles == [
               %{
                 title: "Elixir (programming language)",
                 extract: "",
                 url: "https://en.wikipedia.org/wiki/Elixir_(programming_language)"
               },
               %{
                 title: "Erlang",
                 extract: "",
                 url: "https://en.wikipedia.org/wiki/Erlang"
               }
             ]
    end

    test "returns empty list if no results found" do
      mock_response = %{
        "query" => "nonexistent_query",
        "results" => [],
        "elapsed_ms" => 10.0
      }

      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "http://localhost:8001/search"
        assert opts[:params] == %{q: "nonexistent_query", k: 5}

        {:ok, %{status: 200, body: mock_response}}
      end)

      {:ok, articles} = Wikipedia.search_articles("nonexistent_query")
      assert articles == []
    end

    test "returns an error tuple on HTTP error" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      {:error, reason} = Wikipedia.search_articles("elixir")
      assert reason == "HTTP 500"
    end

    test "returns an error tuple on connection error" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:error, :econnrefused}
      end)

      {:error, reason} = Wikipedia.search_articles("elixir")
      assert reason == {:error, :econnrefused}
    end

    test "returns empty list for invalid search response format" do
      mock_response = %{"some" => "invalid", "data" => "here"}

      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "http://localhost:8001/search"
        assert opts[:params] == %{q: "invalid_format_query", k: 5}

        {:ok, %{status: 200, body: mock_response}}
      end)

      {:ok, articles} = Wikipedia.search_articles("invalid_format_query")
      assert articles == []
    end
  end

  describe "get_article/1" do
    test "returns an article summary on success" do
      mock_response = %{
        "title" => "Elixir (programming language)",
        "extract" => "Elixir is a functional, concurrent, general-purpose programming language...",
        "content_urls" => %{"desktop" => %{"page" => "https://en.wikipedia.org/wiki/Elixir_(programming_language)"}},
        "originalimage" => %{
          "source" =>
            "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
        }
      }

      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
        assert opts[:headers]["User-Agent"] == "Cara-Educational-App/1.0"
        {:ok, %{status: 200, body: mock_response}}
      end)

      {:ok, article} = Wikipedia.get_article("Elixir (programming language)")

      assert article == %{
               title: "Elixir (programming language)",
               extract: "Elixir is a functional, concurrent, general-purpose programming language...",
               url: "https://en.wikipedia.org/wiki/Elixir_(programming_language)",
               image:
                 "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
             }
    end

    test "returns :not_found if article not found" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 404, body: "Not Found"}}
      end)

      {:error, reason} = Wikipedia.get_article("NonExistentArticle")
      assert reason == "Article not found"
    end

    test "returns an error tuple on HTTP error" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      {:error, reason} = Wikipedia.get_article("Elixir")
      assert reason == "HTTP 500"
    end

    test "returns an error tuple on connection error" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:error, :econnrefused}
      end)

      {:error, reason} = Wikipedia.get_article("Elixir")
      assert reason == {:error, :econnrefused}
    end
  end

  describe "get_full_article/1" do
    test "returns a full article on success" do
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
        "batchcomplete" => true,
        "query" => %{
          "normalized" => [
            %{
              "from" => "Elixir (programming language)",
              "to" => "Elixir (programming language)"
            }
          ],
          "pages" => [
            %{
              "pageid" => 12_345,
              "ns" => 0,
              "title" => "Elixir (programming language)",
              "extract" => "Full content of Elixir article..."
            }
          ]
        }
      }

      # Expect for summary fetch
      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
        {:ok, %{status: 200, body: summary_mock_response}}
      end)

      # Expect for full content fetch (using action=query)
      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://en.wikipedia.org/w/api.php"

        assert opts[:params] == %{
                 action: "query",
                 prop: "extracts",
                 titles: "Elixir (programming language)",
                 explaintext: 1,
                 exsectionformat: "plain",
                 format: "json",
                 formatversion: 2
               }

        {:ok, %{status: 200, body: content_mock_response}}
      end)

      {:ok, article} = Wikipedia.get_full_article("Elixir (programming language)")

      assert article == %{
               title: "Elixir (programming language)",
               extract: "Elixir is a functional, concurrent, general-purpose programming language...",
               content: "Full content of Elixir article...",
               url: "https://en.wikipedia.org/wiki/Elixir_(programming_language)",
               image:
                 "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
             }
    end

    test "returns another full article on success" do
      summary_mock_response = %{
        "title" => "Phoenix (web framework)",
        "extract" => "Phoenix is a web framework written in Elixir...",
        "content_urls" => %{"desktop" => %{"page" => "https://en.wikipedia.org/wiki/Phoenix_(web_framework)"}},
        "originalimage" => %{"source" => "https://upload.wikimedia.org/wikipedia/commons/thumb/phoenix.png"}
      }

      content_mock_response = %{
        "batchcomplete" => true,
        "query" => %{
          "normalized" => [
            %{
              "from" => "Phoenix (web framework)",
              "to" => "Phoenix (web framework)"
            }
          ],
          "pages" => [
            %{
              "pageid" => 67_890,
              "ns" => 0,
              "title" => "Phoenix (web framework)",
              "extract" => "Full content of Phoenix framework article..."
            }
          ]
        }
      }

      # Expect for summary fetch
      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Phoenix%20(web%20framework)"
        {:ok, %{status: 200, body: summary_mock_response}}
      end)

      # Expect for full content fetch (using action=query)
      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://en.wikipedia.org/w/api.php"

        assert opts[:params] == %{
                 action: "query",
                 prop: "extracts",
                 titles: "Phoenix (web framework)",
                 explaintext: 1,
                 exsectionformat: "plain",
                 format: "json",
                 formatversion: 2
               }

        {:ok, %{status: 200, body: content_mock_response}}
      end)

      {:ok, article} = Wikipedia.get_full_article("Phoenix (web framework)")

      assert article == %{
               title: "Phoenix (web framework)",
               extract: "Phoenix is a web framework written in Elixir...",
               content: "Full content of Phoenix framework article...",
               url: "https://en.wikipedia.org/wiki/Phoenix_(web_framework)",
               image: "https://upload.wikimedia.org/wikipedia/commons/thumb/phoenix.png"
             }
    end

    test "returns an error if summary fetch fails" do
      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/NonExistentArticle"
        {:ok, %{status: 404, body: "Not Found"}}
      end)

      {:error, reason} = Wikipedia.get_full_article("NonExistentArticle")
      assert reason == "Article not found"
    end

    test "returns an error if content URL cannot be extracted" do
      summary_mock_response = %{
        "title" => "Elixir (programming language)",
        "extract" => "Elixir is a functional, concurrent, general-purpose programming language...",
        # Missing desktop URL
        "content_urls" => %{"mobile" => %{"page" => "https://m.wikipedia.org/wiki/Elixir_(programming_language)"}}
      }

      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
        {:ok, %{status: 200, body: summary_mock_response}}
      end)

      {:error, reason} = Wikipedia.get_full_article("Elixir (programming language)")
      assert reason == "Could not fetch article URL"
    end

    test "returns an error if content fetch fails" do
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

      {:error, reason} = Wikipedia.get_full_article("Elixir (programming language)")
      assert reason == "HTTP 500"
    end

    test "returns an error if summary fetch connection fails" do
      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
        {:error, :nxdomain}
      end)

      {:error, reason} = Wikipedia.get_full_article("Elixir (programming language)")
      assert reason == :nxdomain
    end

    test "returns an error if summary status is unexpected" do
      summary_mock_response = %{
        "title" => "Elixir (programming language)",
        "extract" => "Elixir is a functional, concurrent, general-purpose programming language...",
        "content_urls" => %{"desktop" => %{"page" => "https://en.wikipedia.org/wiki/Elixir_(programming_language)"}},
        "originalimage" => %{
          "source" =>
            "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Elixir_programming_language_logo.svg/500px-Elixir_programming_language_logo.svg.png"
        }
      }

      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "https://en.wikipedia.org/api/rest_v1/page/summary/Elixir%20(programming%20language)"
        # Simulate unexpected status
        {:ok, %{status: 500, body: summary_mock_response}}
      end)

      {:error, reason} = Wikipedia.get_full_article("Elixir (programming language)")
      assert reason == "HTTP 500"
    end

    test "returns an error if content fetch connection fails" do
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

      # Expect for full content fetch to fail with connection error
      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "https://en.wikipedia.org/w/api.php"

        assert opts[:params] == %{
                 action: "query",
                 prop: "extracts",
                 titles: "Elixir (programming language)",
                 explaintext: 1,
                 exsectionformat: "plain",
                 format: "json",
                 formatversion: 2
               }

        {:error, :nxdomain}
      end)

      {:error, reason} = Wikipedia.get_full_article("Elixir (programming language)")
      assert reason == :nxdomain
    end
  end
end
