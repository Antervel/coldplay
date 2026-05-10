defmodule Cara.AI.Guard do
  @moduledoc """
  A module to handle content classification safety checks for chat interactions.
  """
  alias BranchedLLM.BranchedChat
  alias BranchedLLM.Message
  alias Cara.ContentClassifier

  @doc """
  Returns true if classification is enabled for the given role.
  Role can be :student or :llm.
  """
  def should_classify?(role) do
    if Application.get_env(:cara, :disable_guard_globally, false) do
      false
    else
      check_settings_enabled(role)
    end
  end

  defp check_settings_enabled(role) do
    settings = get_settings()

    if settings[:enabled] do
      target_matches?(settings[:target], role)
    else
      false
    end
  end

  defp target_matches?(:all, _role), do: true
  defp target_matches?(:student, :student), do: true
  defp target_matches?(:llm, :llm), do: true
  defp target_matches?(_, _), do: false

  @doc """
  Classifies the content based on the configured scope.
  Returns :safe or :unsafe.
  """
  def classify(text, _role, branched_chat) do
    settings = get_settings()
    scope = settings[:scope] || :latest_message

    text_to_classify =
      if scope == :whole_conversation and branched_chat do
        build_conversation_text(branched_chat, text)
      else
        text
      end

    if ContentClassifier.safe?(text_to_classify) do
      :safe
    else
      :unsafe
    end
  end

  @doc """
  Convenience function to check if content is unsafe.
  """
  def unsafe?(text, role, branched_chat) do
    classify(text, role, branched_chat) == :unsafe
  end

  @doc """
  Returns the configured blocked message.
  """
  def blocked_message do
    get_settings()[:blocked_message] ||
      "Sorry, I can't answer about this topic. What else do you want to know about?"
  end

  defp get_settings do
    Application.get_env(:cara, :content_classifier_settings, [])
  end

  defp build_conversation_text(branched_chat, latest_text) do
    messages = BranchedChat.get_current_messages(branched_chat)

    messages
    |> Enum.reject(&Message.deleted?/1)
    |> Enum.map(fn msg -> msg.content end)
    |> Kernel.++([latest_text])
    |> Enum.join("\n")
  end
end
