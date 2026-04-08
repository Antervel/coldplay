defmodule Cara.SilverBulletTest do
  use Cara.DataCase

  import Mox

  alias Cara.SilverBullet

  setup :verify_on_exit!

  setup do
    # Configure Cara.SilverBullet to use our mock HTTP client
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
    Application.put_env(:cara, :silver_bullet, base_url: "http://localhost:3000")
    :ok
  end

  describe "get_page/1" do
    test "returns page content on success" do
      expect(Cara.HTTPClientMock, :get, fn url, opts ->
        assert url == "http://localhost:3000/.fs/My%20Page.md"
        assert {"X-Sync-Mode", "true"} in opts[:headers]
        {:ok, %{status: 200, body: "# My Page Content"}}
      end)

      assert {:ok, "# My Page Content"} == SilverBullet.get_page("My Page")
    end

    test "works with .md extension in title" do
      expect(Cara.HTTPClientMock, :get, fn url, _opts ->
        assert url == "http://localhost:3000/.fs/My%20Page.md"
        {:ok, %{status: 200, body: "# My Page Content"}}
      end)

      assert {:ok, "# My Page Content"} == SilverBullet.get_page("My Page.md")
    end

    test "returns error when page not found" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 404}}
      end)

      assert {:error, "Page not found"} == SilverBullet.get_page("NonExistent")
    end

    test "returns error on HTTP failure" do
      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 500}}
      end)

      assert {:error, "HTTP error: 500"} == SilverBullet.get_page("ErrorPage")
    end
  end

  describe "save_page/2" do
    test "returns :ok on success" do
      expect(Cara.HTTPClientMock, :put, fn url, opts ->
        assert url == "http://localhost:3000/.fs/New%20Page.md"
        assert opts[:body] == "New Content"
        assert {"Content-Type", "text/markdown"} in opts[:headers]
        assert {"X-Sync-Mode", "true"} in opts[:headers]
        {:ok, %{status: 200}}
      end)

      assert :ok == SilverBullet.save_page("New Page", "New Content")
    end

    test "returns error on failure" do
      expect(Cara.HTTPClientMock, :put, fn _url, _opts ->
        {:ok, %{status: 400}}
      end)

      assert {:error, "HTTP error: 400"} == SilverBullet.save_page("Fail", "Content")
    end
  end
end
