defmodule CaraWeb.LogsHTMLTest do
  use ExUnit.Case, async: true

  alias CaraWeb.LogsHTML

  describe "logs_url/2" do
    test "returns URL with page param" do
      assert LogsHTML.logs_url(1, nil) == "/logs?page=1"
    end

    test "includes search query when present" do
      assert LogsHTML.logs_url(2, "alice") == "/logs?page=2&q=alice"
    end

    test "omits search query when empty string" do
      assert LogsHTML.logs_url(3, "") == "/logs?page=3"
    end
  end

  describe "branch_url/2" do
    test "returns URL for main branch" do
      assert LogsHTML.branch_url("chat-123", "main") == "/logs/chat-123/main"
    end

    test "returns URL for UUID branch" do
      assert LogsHTML.branch_url("chat-abc", "d20c8c9f-0097-43cc-b148-2108f8501a0f") ==
               "/logs/chat-abc/d20c8c9f-0097-43cc-b148-2108f8501a0f"
    end
  end
end
