defmodule CaraWeb.LogsHTMLTest do
  use ExUnit.Case, async: true

  alias CaraWeb.LogsHTML

  describe "logs_url/2 (backward compat)" do
    test "returns URL with page and sort params" do
      url = LogsHTML.logs_url(1, nil)
      assert url =~ "page=1"
      assert url =~ "sort_by=date"
      assert url =~ "sort_dir=desc"
    end

    test "includes search query when present" do
      url = LogsHTML.logs_url(2, "alice")
      assert url =~ "page=2"
      assert url =~ "q=alice"
      assert url =~ "sort_by=date"
      assert url =~ "sort_dir=desc"
    end

    test "omits search query when empty string" do
      url = LogsHTML.logs_url(3, "")
      assert url =~ "page=3"
      assert url =~ "sort_by=date"
      refute url =~ "q="
    end
  end

  describe "logs_url/4" do
    test "includes sort params" do
      url = LogsHTML.logs_url(1, nil, :student, :asc)
      assert url =~ "page=1"
      assert url =~ "sort_by=student"
      assert url =~ "sort_dir=asc"
    end

    test "includes all params together" do
      url = LogsHTML.logs_url(2, "bob", :messages, :desc)
      assert url =~ "page=2"
      assert url =~ "sort_by=messages"
      assert url =~ "sort_dir=desc"
      assert url =~ "q=bob"
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
