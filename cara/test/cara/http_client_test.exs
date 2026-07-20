defmodule Cara.HTTPClientTest do
  use ExUnit.Case, async: true

  alias Cara.HTTPClient

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}/test"}
  end

  describe "get/2" do
    test "makes a GET request and returns response", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

      assert {:ok, %{status: 200, body: "ok"}} = HTTPClient.get(url)
    end

    test "passes options to Req", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

      assert {:ok, %{status: 200}} = HTTPClient.get(url, headers: %{"Accept" => "application/json"})
    end

    test "returns error on connection failure" do
      assert {:error, _reason} = HTTPClient.get("http://localhost:1/nonexistent")
    end
  end

  describe "post/2" do
    test "makes a POST request and returns response", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "POST", "/test", fn conn ->
        Plug.Conn.resp(conn, 201, "created")
      end)

      assert {:ok, %{status: 201, body: "created"}} = HTTPClient.post(url)
    end

    test "sends JSON body", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "POST", "/test", fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "hello"
        Plug.Conn.resp(conn, 200, body)
      end)

      assert {:ok, %{status: 200}} = HTTPClient.post(url, json: %{text: "hello"})
    end

    test "returns error on connection failure" do
      assert {:error, _reason} = HTTPClient.post("http://localhost:1/nonexistent")
    end
  end
end
