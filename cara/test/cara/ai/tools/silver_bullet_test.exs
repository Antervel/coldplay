defmodule Cara.AI.Tools.SilverBulletTest do
  use Cara.DataCase

  import Mox

  alias Cara.AI.Tools.SilverBullet

  setup :verify_on_exit!

  setup do
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
    Application.put_env(:cara, :silver_bullet, base_url: "http://localhost:3000")
    :ok
  end

  describe "silver_bullet_get tool" do
    test "successfully retrieves page content" do
      tool = SilverBullet.silver_bullet_get()

      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: "Wiki Content"}}
      end)

      assert {:ok, result} = tool.callback.(%{"title" => "MyPage"})
      assert result =~ "Content of 'MyPage':"
      assert result =~ "Wiki Content"
    end

    test "handles error when page is not found" do
      tool = SilverBullet.silver_bullet_get()

      expect(Cara.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 404}}
      end)

      assert {:error, reason} = tool.callback.(%{"title" => "NonExistent"})
      assert reason =~ "Page not found"
    end
  end

  describe "silver_bullet_save tool" do
    test "successfully saves page content" do
      tool = SilverBullet.silver_bullet_save()

      expect(Cara.HTTPClientMock, :put, fn _url, opts ->
        assert opts[:body] == "New Content"
        {:ok, %{status: 200}}
      end)

      assert {:ok, result} = tool.callback.(%{"title" => "NewPage", "content" => "New Content"})
      assert result =~ "Successfully saved content"
    end

    test "handles error during save" do
      tool = SilverBullet.silver_bullet_save()

      expect(Cara.HTTPClientMock, :put, fn _url, _opts ->
        {:ok, %{status: 500}}
      end)

      assert {:error, reason} = tool.callback.(%{"title" => "Fail", "content" => "Content"})
      assert reason =~ "HTTP error: 500"
    end
  end
end
