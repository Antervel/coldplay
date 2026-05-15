defmodule Cara.Education.ChatServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias BranchedLLM.BranchedChat
  alias Cara.Education.ChatService
  alias ReqLLM.Context

  setup :verify_on_exit!

  setup do
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)

    # Manage global kill-switch
    original_disabled = Application.get_env(:cara, :disable_guard_globally)
    Application.put_env(:cara, :disable_guard_globally, false)

    on_exit(fn ->
      Application.put_env(:cara, :disable_guard_globally, original_disabled)
    end)

    # Minimal mock socket for broadcasts

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        chat_id: "test-chat",
        student_info: %{name: "Test"}
      }
    }

    {:ok, socket: socket}
  end

  describe "send_message/3 with classification" do
    test "blocks unsafe student message", %{socket: socket} do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :student)

      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))

      # Mock ContentClassifier to say UNSAFE
      expect(Cara.HTTPClientMock, :post, 1, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             sexual: %{label: "NSFW", score: 0.9},
             detoxify: %{
               toxicity: 0.1,
               severe_toxicity: 0.1,
               obscene: 0.1,
               threat: 0.1,
               insult: 0.1,
               identity_attack: 0.1
             }
           }
         }}
      end)

      # We should NOT see an LLM call from here, but we check return value
      assert {:blocked, updated_chat} = ChatService.send_message(chat, "unsafe message", socket)

      messages = BranchedChat.get_current_messages(updated_chat)
      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "unsafe message"
      assert Enum.at(messages, 1).role == :assistant
      assert Enum.at(messages, 1).content =~ "Sorry, I can't answer"
    end

    test "allows safe student message", %{socket: socket} do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :student)

      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))

      # Mock ContentClassifier to say SAFE
      expect(Cara.HTTPClientMock, :post, 1, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             sexual: %{label: "Safe", score: 0.1},
             detoxify: %{
               toxicity: 0.1,
               severe_toxicity: 0.1,
               obscene: 0.1,
               threat: 0.1,
               insult: 0.1,
               identity_attack: 0.1
             }
           }
         }}
      end)

      assert {:send, updated_chat, user_msg, _socket} = ChatService.send_message(chat, "safe message", socket)
      assert user_msg.content == "safe message"
      assert length(BranchedChat.get_current_messages(updated_chat)) == 1
    end
  end

  describe "handle_chunk/4" do
    test "appends chunk to branched chat" do
      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))
      chat = BranchedChat.add_user_message(chat, "Hello")

      {updated_chat, returned_chunk} = ChatService.handle_chunk(chat, "main", "world", "chat-1")

      assert returned_chunk == "world"
      messages = BranchedChat.get_current_messages(updated_chat)
      last_msg = List.last(messages)
      assert last_msg.role == :assistant
      assert last_msg.content == "world"
    end

    test "accumulates multiple chunks" do
      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))
      chat = BranchedChat.add_user_message(chat, "Hello")

      {chat, _} = ChatService.handle_chunk(chat, "main", "Hel", "chat-1")
      {chat, _} = ChatService.handle_chunk(chat, "main", "lo ", "chat-1")
      {updated_chat, _} = ChatService.handle_chunk(chat, "main", "world", "chat-1")

      messages = BranchedChat.get_current_messages(updated_chat)
      last_msg = List.last(messages)
      assert last_msg.content == "Hello world"
    end

    test "returns unmodified chunk when no plugin modifies it" do
      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))
      chat = BranchedChat.add_user_message(chat, "Hello")

      {_, returned_chunk} = ChatService.handle_chunk(chat, "main", "unchanged", "chat-1")

      assert returned_chunk == "unchanged"
    end
  end

  describe "finish_ai_response/4 with classification" do
    test "replaces unsafe LLM response", %{socket: socket} do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :llm)

      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))
      chat = BranchedChat.add_user_message(chat, "Hello")
      chat = BranchedChat.append_chunk(chat, "main", "Unsafe AI response")

      # Mock ContentClassifier to say UNSAFE
      expect(Cara.HTTPClientMock, :post, 1, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             sexual: %{label: "NSFW", score: 0.9},
             detoxify: %{
               toxicity: 0.1,
               severe_toxicity: 0.1,
               obscene: 0.1,
               threat: 0.1,
               insult: 0.1,
               identity_attack: 0.1
             }
           }
         }}
      end)

      llm_context_builder = fn content ->
        ReqLLM.Context.append(BranchedChat.get_current_context(chat), ReqLLM.Context.assistant(content))
      end

      updated_chat = ChatService.finish_ai_response(chat, "main", llm_context_builder, socket)

      messages = BranchedChat.get_current_messages(updated_chat)
      last_msg = List.last(messages)
      assert last_msg.role == :assistant
      assert last_msg.content =~ "Sorry, I can't answer"

      context_messages = BranchedChat.get_current_context(updated_chat).messages
      last_context_msg = List.last(context_messages)

      # Handle ContentPart structs or binary content
      content_text =
        case last_context_msg.content do
          parts when is_list(parts) ->
            Enum.map_join(parts, "", fn
              %{text: t} -> t
              t when is_binary(t) -> t
            end)

          content ->
            content
        end

      assert content_text =~ "Sorry, I can't answer"
    end
  end
end
