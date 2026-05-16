defmodule CaraWeb.LogsControllerTest do
  use CaraWeb.ConnCase, async: true

  alias Cara.Audit
  alias Cara.Audit.Message
  alias Cara.Repo

  setup do
    {:ok, _} =
      Audit.create_session(%{
        chat_id: "chat-ctrl-1",
        student_name: "Test Student",
        student_age: 11,
        student_subject: "History"
      })

    %Message{}
    |> Message.changeset(%{
      chat_id: "chat-ctrl-1",
      message_id: "msg-c1",
      role: "user",
      content: "Test message content",
      branch_id: "main"
    })
    |> Repo.insert!()

    :ok
  end

  describe "GET /logs" do
    test "returns 200 and shows branch list", %{conn: conn} do
      conn = get(conn, ~p"/logs")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "shows student name in list", %{conn: conn} do
      conn = get(conn, ~p"/logs")
      assert html_response(conn, 200) =~ "Test Student"
    end

    test "shows branch column", %{conn: conn} do
      conn = get(conn, ~p"/logs")
      assert html_response(conn, 200) =~ "main"
    end

    test "search filters results", %{conn: conn} do
      conn = get(conn, ~p"/logs?q=Test+Student")
      assert html_response(conn, 200) =~ "Test Student"

      conn = get(conn, ~p"/logs?q=nonexistent")
      refute html_response(conn, 200) =~ "Test Student"
    end

    test "accepts page parameter", %{conn: conn} do
      conn = get(conn, ~p"/logs?page=2")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "defaults invalid page to 1", %{conn: conn} do
      conn = get(conn, ~p"/logs?page=invalid")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "defaults negative page to 1", %{conn: conn} do
      conn = get(conn, ~p"/logs?page=-1")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "accepts sort_by parameter", %{conn: conn} do
      conn = get(conn, ~p"/logs?sort_by=student&sort_dir=asc")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "defaults invalid sort_by to date", %{conn: conn} do
      conn = get(conn, ~p"/logs?sort_by=invalid")
      assert html_response(conn, 200) =~ "Chat Logs"
    end

    test "defaults invalid sort_dir to desc", %{conn: conn} do
      conn = get(conn, ~p"/logs?sort_dir=invalid")
      assert html_response(conn, 200) =~ "Chat Logs"
    end
  end

  describe "GET /logs/:chat_id/:branch_id" do
    test "returns 200 and shows branch conversation", %{conn: conn} do
      conn = get(conn, ~p"/logs/chat-ctrl-1/main")
      assert html_response(conn, 200) =~ "Test Student"
      assert html_response(conn, 200) =~ "Test message content"
    end

    test "shows branch identifier", %{conn: conn} do
      conn = get(conn, ~p"/logs/chat-ctrl-1/main")
      assert html_response(conn, 200) =~ "main"
    end

    test "shows branch without session record", %{conn: conn} do
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-no-session",
        message_id: "msg-orphan",
        role: "user",
        content: "Orphan message",
        branch_id: "main"
      })
      |> Repo.insert!()

      conn = get(conn, ~p"/logs/chat-no-session/main")
      assert html_response(conn, 200) =~ "Unknown Student"
      assert html_response(conn, 200) =~ "Orphan message"
    end

    test "only shows messages for that branch", %{conn: conn} do
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-ctrl-1",
        message_id: "msg-c2",
        role: "user",
        content: "Other branch message",
        branch_id: "alt-branch"
      })
      |> Repo.insert!()

      conn = get(conn, ~p"/logs/chat-ctrl-1/main")
      assert html_response(conn, 200) =~ "Test message content"
      refute html_response(conn, 200) =~ "Other branch message"

      conn = get(conn, ~p"/logs/chat-ctrl-1/alt-branch")
      assert html_response(conn, 200) =~ "Other branch message"
      refute html_response(conn, 200) =~ "Test message content"
    end

    test "returns 404 for unknown branch", %{conn: conn} do
      conn = get(conn, ~p"/logs/nonexistent/main")
      assert conn.status == 404
    end
  end
end
