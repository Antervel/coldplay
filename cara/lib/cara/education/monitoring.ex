defmodule Cara.Education.Monitoring do
  @moduledoc """
  Interface-independent educational monitoring logic.
  Handles broadcasting events to the teacher dashboard.
  """

  @monitoring_topic "teacher:monitor"

  @doc """
  Broadcasts a domain-level event to the monitoring topic.
  """
  def broadcast(event) do
    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(Cara.PubSub, @monitoring_topic, event)
    end
  end

  defp monitoring_enabled? do
    Application.get_env(:cara, :enable_teacher_monitoring, true)
  end

  ## Event helper functions for common monitoring events

  def chat_started(chat_id, student_info) do
    broadcast({:chat_started, %{id: chat_id, student: student_info}})
  end

  def chat_left(chat_id) do
    broadcast({:chat_left, %{id: chat_id}})
  end

  def chat_state(chat_id, student_info, messages) do
    broadcast({:chat_state, %{id: chat_id, student: student_info, messages: messages}})
  end

  def new_message(chat_id, message) do
    broadcast({:new_message, %{chat_id: chat_id, message: message}})
  end

  def message_deleted(chat_id, message_id) do
    broadcast({:message_deleted, %{chat_id: chat_id, message_id: message_id}})
  end

  def teacher_joined do
    broadcast({:teacher_joined, nil})
  end
end
