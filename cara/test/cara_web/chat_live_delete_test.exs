defmodule CaraWeb.ChatLiveDeleteTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  alias Cara.AI.BranchedChat
  alias Cara.AI.Message
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    # Stub health check by default
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    # Initialize test session
    conn = Plug.Test.init_test_session(conn, %{})
    # Fetch the session
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  # Define mock
  setup :verify_on_exit!

  describe "deleting messages" do
    test "can delete an assistant message and it is removed from context", %{conn: conn} do
      # Mock new_context to return a context with one system message
      system_msg = Context.system("System prompt")
      initial_ctx = Context.new([system_msg])
      stub(Cara.AI.ChatMock, :new_context, fn _prompt -> initial_ctx end)

      # Mock reset_context to return a context with only system messages
      stub(Cara.AI.ChatMock, :reset_context, fn ctx ->
        system_msgs = Enum.filter(ctx.messages, fn msg -> msg.role == :system end)
        Context.new(system_msgs)
      end)

      # Mock send_message_stream
      stub(Cara.AI.ChatMock, :send_message_stream, fn message, context, _opts ->
        # Just return the message itself as response for simplicity
        stream = [ReqLLM.StreamChunk.text("Response to #{message}")]

        # The builder appends user and assistant messages to context
        builder = fn content ->
          context
          |> Context.append(Context.user(message))
          |> Context.append(Context.assistant(content))
        end

        stream_response = %StreamResponse{
          context: context,
          model: %ReqLLM.Model{model: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: stream,
          metadata_task: Task.async(fn -> %{} end)
        }

        {:ok, stream_response, builder, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Send a message
      view
      |> form("form", chat: %{message: "Hello AI"})
      |> render_submit()

      :timer.sleep(100)

      # Verify it's there
      html = render(view)
      assert html =~ "Hello AI"
      assert html =~ "Response to Hello AI"

      # Check state
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      # chat_messages: [welcome, user, assistant]
      assert length(current_messages) == 3
      # llm_context: [system, user, assistant]
      assert length(current_context.messages) == 3

      # Now delete the assistant message (idx 2)
      view
      |> render_hook("delete_message", %{"idx" => 2})

      # Verify it's gone from UI
      html = render(view)
      assert html =~ "Hello AI"
      refute html =~ "Response to Hello AI"

      # Verify it's marked as deleted in state
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      # chat_messages still has 3 messages, but one is deleted: true
      assert length(current_messages) == 3
      assert current_messages |> Enum.at(2) |> Message.deleted?()

      # llm_context should be [system, user]
      assert length(current_context.messages) == 2
      assert Enum.at(current_context.messages, 1).role == :user
      assert List.last(current_context.messages).content |> hd() |> Map.get(:text) == "Hello AI"
    end

    test "can delete multiple assistant messages", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _prompt -> Context.new([Context.system("S")]) end)

      stub(Cara.AI.ChatMock, :reset_context, fn ctx ->
        Context.new(Enum.filter(ctx.messages, fn msg -> msg.role == :system end))
      end)

      stub(Cara.AI.ChatMock, :send_message_stream, fn message, context, _opts ->
        builder = fn content ->
          context |> Context.append(Context.user(message)) |> Context.append(Context.assistant(content))
        end

        stream_response = %StreamResponse{
          context: context,
          model: %ReqLLM.Model{model: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: [ReqLLM.StreamChunk.text("R-#{message}")],
          metadata_task: Task.async(fn -> %{} end)
        }

        {:ok, stream_response, builder, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Send 2 messages
      view |> form("form", chat: %{message: "M1"}) |> render_submit()
      :timer.sleep(100)
      view |> form("form", chat: %{message: "M2"}) |> render_submit()
      :timer.sleep(100)

      # chat_messages: [welcome, M1, R-M1, M2, R-M2] (indices 0, 1, 2, 3, 4)
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      assert length(current_messages) == 5
      assert length(current_context.messages) == 5

      # Delete R-M1 (idx 2)
      view |> render_hook("delete_message", %{"idx" => 2})

      # chat_messages: [welcome, M1, R-M1, M2, R-M2] (indices 0, 1, 2, 3, 4)
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      assert length(current_messages) == 5
      assert current_messages |> Enum.at(2) |> Message.deleted?()
      # llm_context should be [S, M1, M2, R-M2]
      assert length(current_context.messages) == 4

      # Delete R-M2 (idx 4)
      view |> render_hook("delete_message", %{"idx" => 4})

      # chat_messages: [welcome, M1, R-M1, M2, R-M2]
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      assert length(current_messages) == 5
      assert current_messages |> Enum.at(4) |> Message.deleted?()
      # llm_context should be [S, M1, M2]
      assert length(current_context.messages) == 3
      assert Enum.at(current_context.messages, 1).role == :user
      assert Enum.at(current_context.messages, 2).role == :user
    end

    test "can delete a user message and it is removed from context", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _prompt -> Context.new([Context.system("S")]) end)

      stub(Cara.AI.ChatMock, :reset_context, fn ctx ->
        Context.new(Enum.filter(ctx.messages, fn msg -> msg.role == :system end))
      end)

      stub(Cara.AI.ChatMock, :send_message_stream, fn message, context, _opts ->
        builder = fn content ->
          context |> Context.append(Context.user(message)) |> Context.append(Context.assistant(content))
        end

        stream_response = %StreamResponse{
          context: context,
          model: %ReqLLM.Model{model: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: [ReqLLM.StreamChunk.text("R-#{message}")],
          metadata_task: Task.async(fn -> %{} end)
        }

        {:ok, stream_response, builder, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Send a message
      view |> form("form", chat: %{message: "User Message"}) |> render_submit()
      :timer.sleep(100)

      # chat_messages: [welcome, User Message, R-User Message]
      # indices: 0, 1, 2
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)

      assert length(current_messages) == 3
      user_msg_id = Enum.at(current_messages, 1).id

      # Delete user message (idx 1)
      view |> render_hook("delete_message", %{"id" => user_msg_id})

      # Verify it's marked as deleted
      state = :sys.get_state(view.pid)
      branched_chat = state.socket.assigns.branched_chat
      current_messages = BranchedChat.get_current_messages(branched_chat)
      current_context = BranchedChat.get_current_context(branched_chat)

      assert current_messages |> Enum.at(1) |> Message.deleted?()

      # llm_context should only have system and assistant message?
      assert length(current_context.messages) == 2
      assert Enum.at(current_context.messages, 1).role == :assistant
    end

    test "message wrapper has correct data attributes", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _prompt -> Context.new([Context.system("S")]) end)
      {:ok, view, _html} = live(conn, ~p"/chat")

      # Welcome message is in branch 'main' at index 0, sender assistant
      # The data attributes are now on the wrapper div
      assert has_element?(view, "#message-wrapper-assistant-0[data-idx='0'][data-sender='assistant'][data-id]")
    end
  end
end
