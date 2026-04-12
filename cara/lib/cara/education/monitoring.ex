defmodule Cara.Education.Monitoring do
  @moduledoc """
  Handles PubSub broadcasting for the teacher monitoring feature.

  This module is responsible for broadcasting chat events to the teacher dashboard.
  It lives in the **education** domain layer, decoupled from the web interface.

  ## Events

  The following events are broadcast on the `"teacher:monitor"` topic:

    * `{:chat_started, %{id: chat_id, student: student_info}}` — A new student chat session
    * `{:chat_left, %{id: chat_id}}` — A student left the chat
    * `{:chat_state, %{id: chat_id, student: student_info, messages: messages}}` — Full chat state
    * `{:new_message, %{chat_id: chat_id, message: message}}` — A new message was added
    * `{:message_deleted, %{chat_id: chat_id, message_id: message_id}}` — A message was deleted

  ## Usage

  Instead of calling `Phoenix.PubSub.broadcast/3` directly from `ChatLive`, use the
  functions in this module. Each function accepts a socket and handles the
  monitoring check internally.

      socket = Monitoring.broadcast_chat_started(socket, student_info)

  """

  @topic "teacher:monitor"

  @type chat_id :: String.t()
  @type student_info :: %{name: String.t(), subject: String.t(), age: String.t(), chat_id: chat_id()}
  @type socket :: Phoenix.LiveView.Socket.t()

  @doc """
  Subscribes the current process to the teacher monitoring topic.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Cara.PubSub, @topic)
  end

  @doc """
  Broadcasts that a chat session has started.
  """
  @spec broadcast_chat_started(socket(), student_info()) :: socket()
  def broadcast_chat_started(socket, student_info) do
    broadcast(socket, {:chat_started, %{id: student_info.chat_id, student: student_info}})
  end

  @doc """
  Broadcasts that a student has left the chat.
  """
  @spec broadcast_chat_left(socket(), chat_id()) :: socket()
  def broadcast_chat_left(socket, chat_id) do
    broadcast(socket, {:chat_left, %{id: chat_id}})
  end

  @doc """
  Broadcasts the full chat state.
  """
  @spec broadcast_chat_state(socket(), chat_id(), student_info(), [map()]) :: socket()
  def broadcast_chat_state(socket, chat_id, student_info, messages) do
    broadcast(socket, {:chat_state, %{id: chat_id, student: student_info, messages: messages}})
  end

  @doc """
  Broadcasts a new message.
  """
  @spec broadcast_new_message(socket(), chat_id(), map()) :: socket()
  def broadcast_new_message(socket, chat_id, message) do
    broadcast(socket, {:new_message, %{chat_id: chat_id, message: message}})
  end

  @doc """
  Broadcasts that a message was deleted.
  """
  @spec broadcast_message_deleted(socket(), chat_id(), String.t()) :: socket()
  def broadcast_message_deleted(socket, chat_id, message_id) do
    broadcast(socket, {:message_deleted, %{chat_id: chat_id, message_id: message_id}})
  end

  @doc """
  Conditionally broadcasts an event if monitoring is enabled.

  This is the internal helper that checks the app config before broadcasting.
  """
  @spec broadcast(socket(), term()) :: socket()
  def broadcast(socket, event) do
    if monitoring_enabled?() do
      Phoenix.PubSub.broadcast(Cara.PubSub, @topic, event)
    end

    socket
  end

  @doc """
  Returns whether teacher monitoring is enabled in the app config.
  """
  @spec monitoring_enabled?() :: boolean()
  def monitoring_enabled? do
    Application.get_env(:cara, :enable_teacher_monitoring, true)
  end
end
