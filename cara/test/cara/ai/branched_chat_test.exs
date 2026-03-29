defmodule Cara.AI.BranchedChatTest do
  use ExUnit.Case, async: true
  alias Cara.AI.BranchedChat
  alias ReqLLM.Context

  defp mock_chat_module do
    Cara.AI.ChatMock
  end

  defp initial_setup do
    initial_messages = [%{id: "welcome", sender: :assistant, content: "Welcome!", deleted: false}]
    initial_context = Context.new([Context.system("System prompt")])
    BranchedChat.new(mock_chat_module(), initial_messages, initial_context)
  end

  test "new/3 initializes a branched chat with a main branch" do
    chat = initial_setup()
    assert chat.current_branch_id == "main"
    assert chat.branch_ids == ["main"]
    assert Map.has_key?(chat.branches, "main")

    main_branch = chat.branches["main"]
    assert main_branch.name == "Main Conversation"
    assert length(main_branch.messages) == 1
    assert main_branch.parent_branch_id == nil
  end

  test "add_user_message/2 adds a message to the current branch" do
    chat = initial_setup()
    chat = BranchedChat.add_user_message(chat, "Hello")

    messages = BranchedChat.get_current_messages(chat)
    assert length(messages) == 2
    assert List.last(messages).content == "Hello"
    assert List.last(messages).sender == :user
  end

  test "branch_off/2 creates a new branch from a message" do
    # 1. Setup: main branch with 3 messages
    chat = initial_setup()
    chat = BranchedChat.add_user_message(chat, "Msg 1")
    user_msg_id = List.last(BranchedChat.get_current_messages(chat)).id

    # Mock reset_context for rebuild_context_from_messages
    import Mox
    stub(Cara.AI.ChatMock, :reset_context, fn _ctx -> Context.new([Context.system("System prompt")]) end)

    # 2. Branch off from Msg 1
    chat = BranchedChat.branch_off(chat, user_msg_id)

    assert chat.current_branch_id != "main"
    assert length(chat.branch_ids) == 2

    new_branch = chat.branches[chat.current_branch_id]
    assert new_branch.name == ""
    assert new_branch.parent_branch_id == "main"
    assert new_branch.parent_message_id == user_msg_id
    # Welcome + Msg 1
    assert length(new_branch.messages) == 2

    assert chat.child_branches[user_msg_id] == [chat.current_branch_id]
  end

  test "add_user_message/2 updates branch name if it is empty" do
    chat = initial_setup()
    import Mox
    stub(Cara.AI.ChatMock, :reset_context, fn _ctx -> Context.new([Context.system("S")]) end)

    # 1. Branch off
    chat = BranchedChat.branch_off(chat, hd(BranchedChat.get_current_messages(chat)).id)
    new_branch_id = chat.current_branch_id
    assert chat.branches[new_branch_id].name == ""

    # 2. Add first message in branch
    chat = BranchedChat.add_user_message(chat, "What is 2+2?")
    assert chat.branches[new_branch_id].name == "What is 2+2?"

    # 3. Add second message - name should NOT change
    chat = BranchedChat.add_user_message(chat, "And 3+3?")
    assert chat.branches[new_branch_id].name == "What is 2+2?"
  end

  test "switch_branch/2 changes the active branch" do
    chat = initial_setup()
    chat = BranchedChat.add_user_message(chat, "Msg 1")
    user_msg_id = List.last(BranchedChat.get_current_messages(chat)).id

    import Mox
    stub(Cara.AI.ChatMock, :reset_context, fn _ctx -> Context.new([Context.system("S")]) end)

    chat = BranchedChat.branch_off(chat, user_msg_id)
    new_branch_id = chat.current_branch_id

    chat = BranchedChat.switch_branch(chat, "main")
    assert chat.current_branch_id == "main"

    chat = BranchedChat.switch_branch(chat, new_branch_id)
    assert chat.current_branch_id == new_branch_id
  end

  test "delete_message/2 marks message as deleted and rebuilds context" do
    chat = initial_setup()
    chat = BranchedChat.add_user_message(chat, "To delete")
    msg_id = List.last(BranchedChat.get_current_messages(chat)).id

    import Mox
    # rebuild_context_from_messages will call reset_context
    expect(Cara.AI.ChatMock, :reset_context, 1, fn _ctx -> Context.new([Context.system("S")]) end)

    chat = BranchedChat.delete_message(chat, msg_id)

    messages = BranchedChat.get_current_messages(chat)
    assert Enum.find(messages, &(&1.id == msg_id)).deleted == true

    # Context should only have system message now
    context = BranchedChat.get_current_context(chat)
    assert length(context.messages) == 1
    assert hd(context.messages).role == :system
  end
end
