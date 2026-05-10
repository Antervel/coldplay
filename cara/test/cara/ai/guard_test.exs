defmodule Cara.AI.GuardTest do
  use ExUnit.Case, async: false
  import Mox

  alias BranchedLLM.BranchedChat
  alias Cara.AI.Guard
  alias ReqLLM.Context

  setup :verify_on_exit!

  setup do
    # Save original settings
    original_settings = Application.get_env(:cara, :content_classifier_settings)
    original_disabled = Application.get_env(:cara, :disable_guard_globally)

    # Enable for these tests
    Application.put_env(:cara, :disable_guard_globally, false)

    on_exit(fn ->
      Application.put_env(:cara, :content_classifier_settings, original_settings)
      Application.put_env(:cara, :disable_guard_globally, original_disabled)
    end)

    :ok
  end

  describe "should_classify?/1" do
    test "returns false when disabled" do
      Application.put_env(:cara, :content_classifier_settings, enabled: false)
      assert Guard.should_classify?(:student) == false
      assert Guard.should_classify?(:llm) == false
    end

    test "returns true for both when enabled and target is :all" do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :all)
      assert Guard.should_classify?(:student) == true
      assert Guard.should_classify?(:llm) == true
    end

    test "returns true only for student when target is :student" do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :student)
      assert Guard.should_classify?(:student) == true
      assert Guard.should_classify?(:llm) == false
    end

    test "returns true only for llm when target is :llm" do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, target: :llm)
      assert Guard.should_classify?(:student) == false
      assert Guard.should_classify?(:llm) == true
    end
  end

  describe "classify/3" do
    setup do
      Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
      :ok
    end

    test "returns :safe when ContentClassifier says so" do
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

      assert Guard.classify("hello", :student, nil) == :safe
    end

    test "returns :unsafe when ContentClassifier says so" do
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

      assert Guard.classify("bad stuff", :student, nil) == :unsafe
    end

    test "uses whole conversation when configured" do
      Application.put_env(:cara, :content_classifier_settings, enabled: true, scope: :whole_conversation)

      chat = BranchedChat.new(Cara.AI.Chat, [], Context.new([]))
      chat = BranchedChat.add_user_message(chat, "Hello")

      expect(Cara.HTTPClientMock, :post, 1, fn _url, opts ->
        # It should join "Hello" and "How are you?"
        assert opts[:json][:text] == "Hello\nHow are you?"

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

      assert Guard.classify("How are you?", :student, chat) == :safe
    end
  end

  describe "blocked_message/0" do
    test "returns configured message" do
      Application.put_env(:cara, :content_classifier_settings, blocked_message: "STOP!")
      assert Guard.blocked_message() == "STOP!"
    end

    test "returns default message when not configured" do
      Application.put_env(:cara, :content_classifier_settings, [])
      assert Guard.blocked_message() =~ "Sorry, I can't answer"
    end
  end
end
