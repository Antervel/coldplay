defmodule CaraWeb.ChatLive.FooterComponent do
  @moduledoc """
  LiveComponent for the chat input form.
  Handles its own validation and submission events.
  """
  use CaraWeb, :live_component

  def render(assigns) do
    ~H"""
    <footer class="bg-[#EEEFF5] p-4 shadow-md">
      <form phx-submit="submit_message" phx-hook="ChatScroll" id="chat-form" phx-target={@myself}>
        <div class="flex items-end">
          <textarea
            name="chat[message]"
            id="chat-form_message"
            placeholder="Type your message..."
            phx-change="validate"
            phx-hook="ChatInput"
            class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-400 bg-white text-black resize-none max-h-40"
            value={@message_data["message"]}
          ></textarea>
          <button
            type="submit"
            class="ml-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-400"
          >
            Send
          </button>
        </div>
      </form>
    </footer>
    """
  end

  def handle_event("validate", %{"chat" => params}, socket) do
    updated_message_data = Map.merge(socket.assigns.message_data, params)
    {:noreply, assign(socket, message_data: updated_message_data)}
  end

  def handle_event("submit_message", %{"chat" => %{"message" => message}}, socket) do
    send(self(), {:submit_message, message})
    {:noreply, assign(socket, message_data: %{"message" => ""})}
  end
end
