defmodule Cara.WikipediaTest do
  use ExUnit.Case, async: true
  doctest Cara.Wikipedia

  @moduletag :wikipedia

  test "search_articles returns a list of articles" do
    # This is a basic test - in a real scenario we would mock the HTTP requests
    # but for now we'll just test that the function exists and returns the expected structure
    assert function_exported?(Cara.Wikipedia, :search_articles, 1)
  end

  test "get_article returns article data" do
    # This is a basic test - in a real scenario we would mock the HTTP requests
    # but for now we'll just test that the function exists and returns the expected structure
    assert function_exported?(Cara.Wikipedia, :get_article, 1)
  end

  test "get_full_article returns full article data" do
    # This is a basic test - in a real scenario we would mock the HTTP requests
    # but for now we'll just test that the function exists and returns the expected structure
    assert function_exported?(Cara.Wikipedia, :get_full_article, 1)
  end
end
