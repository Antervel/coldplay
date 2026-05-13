defmodule Cara.AuditTest do
  use Cara.DataCase, async: true

  alias Cara.Audit
  alias Cara.Audit.Message
  alias Cara.Repo

  describe "create_session/1" do
    test "creates an audit session" do
      attrs = %{
        chat_id: "chat-test-1",
        student_name: "Alice",
        student_age: 12,
        student_subject: "Math"
      }

      assert {:ok, session} = Audit.create_session(attrs)
      assert session.chat_id == "chat-test-1"
      assert session.student_name == "Alice"
      assert session.student_age == 12
      assert session.student_subject == "Math"
    end

    test "requires chat_id" do
      assert {:error, changeset} = Audit.create_session(%{student_name: "Bob"})
      assert "can't be blank" in errors_on(changeset).chat_id
    end

    test "enforces unique chat_id" do
      Audit.create_session(%{chat_id: "chat-dup"})
      assert {:error, changeset} = Audit.create_session(%{chat_id: "chat-dup"})
      assert "has already been taken" in errors_on(changeset).chat_id
    end
  end

  describe "list_branches/1" do
    setup do
      {:ok, _} =
        Audit.create_session(%{
          chat_id: "chat-list-1",
          student_name: "Alice",
          student_age: 10,
          student_subject: "Math"
        })

      {:ok, _} =
        Audit.create_session(%{
          chat_id: "chat-list-2",
          student_name: "Bob",
          student_age: 14,
          student_subject: "Science"
        })

      # Insert messages for chat-list-1 on main branch
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-list-1",
        message_id: "msg-1",
        role: "user",
        content: "What is 2+2?",
        branch_id: "main"
      })
      |> Repo.insert!()

      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-list-1",
        message_id: "msg-2",
        role: "assistant",
        content: "4",
        branch_id: "main"
      })
      |> Repo.insert!()

      # Insert message for chat-list-1 on a side branch
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-list-1",
        message_id: "msg-2b",
        role: "user",
        content: "What about 3+3?",
        branch_id: "branch-alt"
      })
      |> Repo.insert!()

      # Insert message for chat-list-2
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-list-2",
        message_id: "msg-3",
        role: "user",
        content: "What is photosynthesis?",
        branch_id: "main"
      })
      |> Repo.insert!()

      :ok
    end

    test "returns each (chat_id, branch_id) as separate entry" do
      {branches, total} = Audit.list_branches()

      assert total == 3
      assert length(branches) == 3

      chat1_main = Enum.find(branches, &(&1.chat_id == "chat-list-1" && &1.branch_id == "main"))
      assert chat1_main.student_name == "Alice"
      assert chat1_main.message_count == 2

      chat1_alt = Enum.find(branches, &(&1.chat_id == "chat-list-1" && &1.branch_id == "branch-alt"))
      assert chat1_alt.student_name == "Alice"
      assert chat1_alt.message_count == 1

      chat2 = Enum.find(branches, &(&1.chat_id == "chat-list-2"))
      assert chat2.student_name == "Bob"
      assert chat2.message_count == 1
    end

    test "shows branches without session records" do
      %Message{}
      |> Message.changeset(%{
        chat_id: "chat-no-session",
        message_id: "msg-orphan",
        role: "user",
        content: "I have no session",
        branch_id: "main"
      })
      |> Repo.insert!()

      {branches, total} = Audit.list_branches()

      assert total == 4
      orphan = Enum.find(branches, &(&1.chat_id == "chat-no-session"))
      assert orphan.student_name == nil
      assert orphan.message_count == 1
    end

    test "includes first user content preview" do
      {branches, _} = Audit.list_branches()

      chat1_main = Enum.find(branches, &(&1.chat_id == "chat-list-1" && &1.branch_id == "main"))
      assert chat1_main.first_user_content =~ "What is 2+2?"
    end

    test "filters by student name" do
      {branches, total} = Audit.list_branches(search: "Alice")

      assert total == 2
      assert Enum.all?(branches, &(&1.student_name == "Alice"))
    end

    test "filters by message content" do
      {branches, total} = Audit.list_branches(search: "photosynthesis")

      assert total == 1
      assert hd(branches).chat_id == "chat-list-2"
    end

    test "returns empty for non-matching search" do
      {branches, total} = Audit.list_branches(search: "nonexistent")

      assert total == 0
      assert branches == []
    end
  end

  describe "get_session/1" do
    test "returns session by chat_id" do
      Audit.create_session(%{chat_id: "chat-get", student_name: "Eve"})

      session = Audit.get_session("chat-get")
      assert session.student_name == "Eve"
    end

    test "returns nil for unknown chat_id" do
      assert Audit.get_session("nonexistent") == nil
    end
  end

  describe "list_messages_for_branch/2" do
    setup do
      msgs = [
        %{chat_id: "chat-br", message_id: "m1", role: "user", content: "Hello", branch_id: "main"},
        %{chat_id: "chat-br", message_id: "m2", role: "assistant", content: "Hi!", branch_id: "main"},
        %{chat_id: "chat-br", message_id: "m3", role: "user", content: "Branch Q", branch_id: "alt"}
      ]

      for attrs <- msgs do
        %Message{}
        |> Message.changeset(attrs)
        |> Repo.insert!()
      end

      :ok
    end

    test "returns messages for specific branch only" do
      result = Audit.list_messages_for_branch("chat-br", "main")

      assert length(result) == 2
      assert Enum.all?(result, &(&1.branch_id == "main"))
    end

    test "messages are ordered by inserted_at" do
      result = Audit.list_messages_for_branch("chat-br", "main")

      assert Enum.at(result, 0).content == "Hello"
      assert Enum.at(result, 1).content == "Hi!"
    end

    test "returns empty list for non-existent branch" do
      result = Audit.list_messages_for_branch("chat-br", "nonexistent")
      assert result == []
    end

    test "returns empty list for non-existent chat" do
      result = Audit.list_messages_for_branch("nope", "main")
      assert result == []
    end
  end
end
