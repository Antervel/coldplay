defmodule Cara.Plugins.AuditPluginTest do
  use Cara.DataCase, async: true

  alias Cara.Audit.Message
  alias Cara.Education.MessagePipeline
  alias Cara.Plugins.AuditPlugin
  alias Cara.Repo
  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox

  setup do
    # Use synchronous insert in tests so we can assert on DB state
    original_fn = Application.get_env(:cara, :audit_insert_fn)
    Application.put_env(:cara, :audit_insert_fn, &sync_insert/1)

    on_exit(fn ->
      if original_fn do
        Application.put_env(:cara, :audit_insert_fn, original_fn)
      else
        Application.delete_env(:cara, :audit_insert_fn)
      end
    end)

    :ok
  end

  describe "default_insert/1" do
    test "uses Task.start for fire-and-forget insert when no override is set" do
      branched_chat = %{current_branch_id: "main", branches: %{}}

      message_obj = %{id: "msg-fire", role: :user, content: "Fire and forget", metadata: %{}}

      context = %MessagePipeline.Context{
        content: "Fire and forget",
        role: :student,
        event: :on_message,
        branched_chat: branched_chat,
        chat_id: "chat-fire",
        assigns: %{message_obj: message_obj},
        metadata: %{}
      }

      # Temporarily remove the override so default_insert runs
      Application.delete_env(:cara, :audit_insert_fn)

      # Allow the repo for this test process so the spawned task can use it
      SQLSandbox.allow(Cara.Repo, self(), self())
      SQLSandbox.mode(Cara.Repo, {:shared, self()})

      AuditPlugin.on_message(context, [])

      # Wait for the Task to complete
      Process.sleep(100)

      row = Repo.one(Message)
      assert row.chat_id == "chat-fire"
      assert row.message_id == "msg-fire"
      assert row.content == "Fire and forget"
    after
      # Restore the test override
      Application.put_env(:cara, :audit_insert_fn, &sync_insert/1)
      SQLSandbox.mode(Cara.Repo, :manual)
    end
  end

  describe "on_message/2" do
    test "persists message to audit_messages table" do
      branched_chat = %{
        current_branch_id: "main",
        branches: %{"main" => %{messages: []}}
      }

      message_obj = %{id: "msg-123", role: :user, content: "Hello world", metadata: %{}}

      context = %MessagePipeline.Context{
        content: "Hello world",
        role: :student,
        event: :on_message,
        branched_chat: branched_chat,
        chat_id: "chat-abc",
        assigns: %{message_obj: message_obj},
        metadata: %{safety_score: 0.1}
      }

      AuditPlugin.on_message(context, [])

      row = Repo.one(Message)
      assert row.chat_id == "chat-abc"
      assert row.message_id == "msg-123"
      assert row.role == "user"
      assert row.content == "Hello world"
      assert row.branch_id == "main"
      assert row.metadata == %{"safety_score" => 0.1}
    end

    test "skips insert when message_obj is missing" do
      context = %MessagePipeline.Context{
        content: "Hello",
        role: :student,
        event: :on_message,
        branched_chat: %{current_branch_id: "main", branches: %{}},
        chat_id: "chat-abc",
        assigns: %{},
        metadata: %{}
      }

      AuditPlugin.on_message(context, [])

      assert Repo.one(Message) == nil
    end

    test "skips insert when chat_id is missing" do
      message_obj = %{id: "msg-456", role: :assistant, content: "Hi", metadata: %{}}

      context = %MessagePipeline.Context{
        content: "Hi",
        role: :llm,
        event: :on_message,
        branched_chat: %{current_branch_id: "main", branches: %{}},
        chat_id: nil,
        assigns: %{message_obj: message_obj},
        metadata: %{}
      }

      AuditPlugin.on_message(context, [])

      assert Repo.one(Message) == nil
    end

    test "returns context unchanged" do
      branched_chat = %{current_branch_id: "main", branches: %{}}

      message_obj = %{id: "msg-789", role: :assistant, content: "Response", metadata: %{}}

      context = %MessagePipeline.Context{
        content: "Response",
        role: :llm,
        event: :on_message,
        branched_chat: branched_chat,
        chat_id: "chat-xyz",
        assigns: %{message_obj: message_obj},
        metadata: %{}
      }

      result = AuditPlugin.on_message(context, [])
      assert result == context
    end
  end

  defp sync_insert(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end
end
