defmodule CaraWeb.ChatLiveBranchTest do
  use CaraWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  alias BranchedLLM.BranchedChat
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse

  setup %{conn: conn} do
    # Stub health check
    stub(Cara.AI.ChatMock, :health_check, fn -> :ok end)

    # Mock new_context
    stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([Context.system("test")]) end)

    # Mock reset_context
    stub(Cara.AI.ChatMock, :reset_context, fn context ->
      # Find system message or return new one
      system_msg = Enum.find(context.messages, fn m -> m.role == :system end) || Context.system("test")
      Context.new([system_msg])
    end)

    # Initialize test session
    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "10", subject: "Math", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  setup :verify_on_exit!

  test "user can branch off from a message", %{conn: conn} do
    # 1. Mount Chat
    {:ok, view, _html} = live(conn, ~p"/chat")

    # 2. Send a message
    stub(Cara.AI.ChatMock, :send_message_stream, fn "Hello", _ctx, _opts ->
      {:ok,
       %StreamResponse{
         stream: [ReqLLM.StreamChunk.text("Hi there!")],
         context: Context.new([]),
         model: %ReqLLM.Model{model: "test", provider: :openai},
         cancel: fn -> :ok end,
         metadata_task: Task.async(fn -> %{} end)
       }, fn content -> Context.new([Context.assistant(content)]) end, []}
    end)

    view |> form("#chat-form", chat: %{message: "Hello"}) |> render_submit()
    Process.sleep(100)

    assert render(view) =~ "Hi there!"

    # 3. Find a message ID to branch off from
    # Let's look at the messages in assigns
    state = :sys.get_state(view.pid)
    branched_chat = state.socket.assigns.branched_chat
    chat_messages = BranchedChat.get_current_messages(branched_chat)

    # There should be 3 messages: Welcome, User "Hello", AI "Hi there!"
    assert length(chat_messages) == 3
    [_welcome, user_msg, _ai_msg] = chat_messages

    # 4. Branch off from the user message
    view |> render_hook("branch_off", %{id: user_msg.id})

    # 5. Verify state after branching
    new_state = :sys.get_state(view.pid)
    new_branched_chat = new_state.socket.assigns.branched_chat
    new_branch_id = new_branched_chat.current_branch_id
    assert new_branch_id != "main"
    assert length(new_branched_chat.branch_ids) == 2
    # Welcome + User "Hello"
    assert length(BranchedChat.get_current_messages(new_branched_chat)) == 2

    # Verify hierarchy
    new_branch = new_branched_chat.branches[new_branch_id]
    assert new_branch.name == ""
    assert new_branch.parent_branch_id == "main"
    assert new_branch.parent_message_id == user_msg.id
    assert Map.has_key?(new_branched_chat.child_branches, user_msg.id)
    assert new_branched_chat.child_branches[user_msg.id] == [new_branch_id]

    # UI should show "New branch..."
    assert render(view) =~ "New branch..."

    # 5.5 Send a message in the NEW branch to update its name
    stub(Cara.AI.ChatMock, :send_message_stream, fn "What time is it?", _ctx, _opts ->
      {:ok,
       %StreamResponse{
         stream: [ReqLLM.StreamChunk.text("It is now.")],
         context: Context.new([]),
         model: %ReqLLM.Model{model: "test", provider: :openai},
         cancel: fn -> :ok end,
         metadata_task: Task.async(fn -> %{} end)
       }, fn content -> Context.new([Context.assistant(content)]) end, []}
    end)

    view |> form("#chat-form", chat: %{message: "What time is it?"}) |> render_submit()
    Process.sleep(100)

    # UI should now show the new name
    assert render(view) =~ "What time is it?"
    refute render(view) =~ "New branch..."

    assert render(view) =~ "Hello"

    # AI response should be absent from the NEW branch
    # (In static version, only the current branch is rendered)
    refute render(view) =~ "Hi there!"

    # 6. Switch back to main branch

    view |> render_click("switch_branch", %{id: "main"})

    back_state = :sys.get_state(view.pid)
    back_branched_chat = back_state.socket.assigns.branched_chat
    assert back_branched_chat.current_branch_id == "main"
    assert length(BranchedChat.get_current_messages(back_branched_chat)) == 3
    assert render(view) =~ "Hi there!"
  end

  test "toggling sidebars", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chat")

    # Initially show_branches is false
    assert :sys.get_state(view.pid).socket.assigns.show_branches == false

    view |> render_click("toggle_branches")
    assert :sys.get_state(view.pid).socket.assigns.show_branches == true

    view |> render_click("toggle_branches")
    assert :sys.get_state(view.pid).socket.assigns.show_branches == false
  end
end
