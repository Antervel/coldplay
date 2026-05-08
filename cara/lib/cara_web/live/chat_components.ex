defmodule CaraWeb.ChatComponents do
  @moduledoc "Components specifically for the Chat interface."
  use CaraWeb, :html

  attr :message, :map, required: true
  attr :idx, :integer, required: true
  attr :last_idx, :integer, required: true
  attr :active_task, :any, default: nil
  attr :tool_status, :string, default: nil
  attr :bubble_width, :string, default: "40%"
  attr :branched_chat, :map, default: nil

  def chat_message(assigns) do
    ~H"""
    <div class={"flex w-full #{if @message.sender == :user, do: "justify-end", else: "justify-start"}"}>
      <div class={"flex items-start gap-4 w-full #{if @message.sender == :user, do: "flex-row-reverse", else: "flex-row"}"}>
        <img
          src={if @message.sender == :user, do: ~p"/images/student.svg", else: ~p"/images/robot.svg"}
          class="w-12 h-12 flex-shrink-0 mt-1 object-cover"
          alt={if @message.sender == :user, do: "Student Avatar", else: "Robot Avatar"}
        />
        <div
          class={"relative flex-1 flex items-center #{if @message.sender == :user, do: "justify-end", else: "justify-start"}"}
          id={"message-wrapper-#{@message.sender}-#{@idx}"}
          data-idx={@idx}
          data-id={@message.id}
          data-sender={@message.sender}
        >
          <% _is_active = @idx == @last_idx && @active_task != nil %>
          <div
            phx-hook="MessageContentSync"
            id={"message-content-#{@message.id}"}
            class={"#{if @message.sender == :user, do: "bg-[#FFFFBC]", else: "bg-[#F5F5F5]"} text-black"}
            phx-update="ignore"
            style={"max-width: #{@bubble_width}; box-shadow: 0px 2px 6px 0px #00000040; border-radius: 8px; padding: 12px 16px; transform: rotate(0deg); opacity: 1;"}
          >
            {render_markdown(
              @message.content,
              "#{@message.id}-#{if @branched_chat, do: @branched_chat.current_branch_id, else: "main"}"
            )}
          </div>
          <% show_stop = @active_task && @idx == @last_idx && @message.sender == :assistant && is_nil(@tool_status) %>
          <div class="relative ml-2">
            <button
              type="button"
              class={"p-1 rounded-full text-black hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 #{if show_stop, do: "bg-red-200 hover:bg-red-300", else: "bg-gray-200"}"}
              data-action={if show_stop, do: "cancel", else: "open-context-menu"}
              phx-click={if show_stop, do: "cancel", else: nil}
              title={if show_stop, do: "Stop generating", else: "Options"}
            >
              <%= if show_stop do %>
                <span class="hero-stop inline-block w-5 h-5 text-red-600"></span>
              <% else %>
                <span class="hero-ellipsis-vertical inline-block w-5 h-5"></span>
              <% end %>
            </button>
            <%= unless show_stop do %>
              <div
                id={"context-menu-#{@message.id}"}
                class="hidden absolute z-50 bg-white rounded-md shadow-lg p-1 transition-all duration-200 ease-out text-black min-w-[160px]"
                style={"top: 100%; #{if @message.sender == :user, do: "right: 0;", else: "left: 0;"}"}
              >
                <button
                  class="flex items-center w-full text-left px-3 py-1.5 text-sm text-black hover:bg-blue-500 hover:text-white rounded-md"
                  data-action="copy"
                  data-id={@message.id}
                  data-message-content={@message.content}
                >
                  <span class="hero-clipboard inline-block w-4 h-4 mr-2"></span> Copy
                </button>
                <button
                  class="flex items-center w-full text-left px-3 py-1.5 text-sm text-black hover:bg-blue-500 hover:text-white rounded-md"
                  data-action="play"
                  data-id={@message.id}
                  data-message-content={@message.content}
                >
                  <span class="hero-speaker-wave inline-block w-4 h-4 mr-2"></span> Play
                </button>
                <button
                  class="flex items-center w-full text-left px-3 py-1.5 text-sm text-black hover:bg-blue-500 hover:text-white rounded-md border-t border-gray-100 mt-1"
                  data-action="branch"
                  data-id={@message.id}
                >
                  <span class="hero-arrow-uturn-right inline-block w-4 h-4 mr-2"></span> Branch off
                </button>
                <button
                  class="flex items-center w-full text-left px-3 py-1.5 text-sm text-red-600 hover:bg-red-600 hover:text-white rounded-md"
                  data-action="delete"
                  data-id={@message.id}
                >
                  <span class="hero-trash inline-block w-4 h-4 mr-2"></span> Delete
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :student_info, :map, required: true
  attr :app_version, :string, required: true
  attr :show_sidebar, :boolean, required: true
  attr :vm, :map, required: true

  def chat_header(assigns) do
    ~H"""
    <header class="bg-blue-600 p-4 shadow-md text-white">
      <div class="w-full flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="relative">
            <button
              type="button"
              class="text-white hover:text-gray-200 focus:outline-none p-1 rounded-md hover:bg-blue-700 transition-colors"
              title="Menu"
              phx-click={JS.push("toggle", value: %{what: "sidebar"})}
            >
              <span class="hero-bars-3 block w-6 h-6"></span>
            </button>
            <div
              :if={@show_sidebar}
              phx-click-away={JS.push("toggle", value: %{what: "sidebar"})}
              class="absolute left-0 mt-2 w-64 bg-white rounded-lg shadow-xl z-50 py-2 text-black ring-1 ring-black/5 animate-in fade-in zoom-in duration-100 origin-top-left"
            >
              <div class="px-4 py-3 border-b border-gray-100 mb-2">
                <p class="text-xs font-bold text-gray-400 uppercase tracking-wider mb-1">Student Info</p>
                <p class="font-bold text-blue-600">{@student_info.name}</p>
                <p class="text-xs text-gray-500">{@student_info.subject} (Age {@student_info.age})</p>
              </div>
              <a
                href="/settings"
                class="w-full flex items-center gap-3 px-4 py-2 text-left hover:bg-blue-50 transition-colors group"
              >
                <span class="hero-cog-6-tooth block w-5 h-5 text-gray-400 group-hover:text-blue-500"></span>
                <span class="font-medium text-sm">Settings</span>
              </a>
              <div class="mt-2 pt-2 border-t border-gray-100">
                <a
                  href="/student"
                  phx-navigate
                  class="w-full flex items-center gap-3 px-4 py-2 text-left hover:bg-red-50 text-red-600 transition-colors group"
                >
                  <span class="hero-arrow-left-on-rectangle block w-5 h-5 opacity-70 group-hover:opacity-100"></span>
                  <span class="font-medium text-sm">Leave Chat</span>
                </a>
              </div>
            </div>
          </div>
          <h1 class="flex items-baseline gap-2" style="font-size: 22px; line-height: 100%; letter-spacing: 0%;">
            <span style="font-family: 'Permanent Marker', cursive; font-weight: 400;">Cara</span>
            <span class="text-sm font-sans opacity-80">v.{@app_version}</span>
          </h1>
          <%= if !@vm.is_main_branch do %>
            <div class="flex items-center gap-2 ml-4 px-3 py-1 bg-blue-700/50 rounded-full border border-blue-400/30 text-xs">
              <span class="opacity-60">Path:</span>
              <span class="font-semibold truncate max-w-[200px]">{@vm.current_branch_name}</span>
              <button phx-click="switch_branch" phx-value-id="main" class="ml-1 hover:text-blue-200" title="Return to Main">
                <span class="hero-arrow-uturn-left inline-block w-3 h-3"></span>
              </button>
            </div>
          <% end %>
        </div>
        <a
          href="/student"
          phx-navigate
          class="bg-red-500 hover:bg-red-700 text-white font-bold flex items-center justify-center"
          style="width: 128px; height: 41px; border-radius: 10px; padding: 12px 32px; gap: 10px; transform: rotate(0deg); opacity: 1;"
        >
          Goodbye!
        </a>
      </div>
    </header>
    """
  end

  attr :message_data, :map, required: true

  def chat_input(assigns) do
    ~H"""
    <textarea
      name="chat[message]"
      id="chat-form_message"
      placeholder="Type your message..."
      phx-change="validate"
      phx-hook="ChatInput"
      class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-400 bg-white text-black resize-none max-h-40"
      value={@message_data["message"]}
    ></textarea>
    """
  end

  attr :message_data, :map, required: true

  def chat_footer(assigns) do
    ~H"""
    <footer class="bg-[#EEEFF5] p-4 shadow-md">
      <form phx-submit="submit_message" phx-hook="ChatScroll" id="chat-form">
        <div class="flex items-end">
          <.chat_input message_data={@message_data} />
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

  attr :show_branches, :boolean, required: true
  attr :show_notes, :boolean, required: true
  attr :notes, :string, required: true
  attr :branched_chat, :map, required: true
  attr :vm, :map, required: true

  def right_panels(assigns) do
    ~H"""
    <div class={"relative h-full bg-white shadow-[-4px_0_15px_-3px_rgba(0,0,0,0.1)] transition-all duration-300 flex-shrink-0 #{if @vm.show_any_right_panel, do: "w-[400px]", else: "w-0"}"}>
      <button
        phx-click={JS.push("toggle", value: %{what: "notes"})}
        class="absolute left-0 top-[46%] -translate-x-full -translate-y-1/2 bg-blue-600 text-white px-2 py-4 rounded-l-lg shadow-md hover:bg-blue-700 transition-colors focus:outline-none flex flex-col items-center gap-2 z-10"
        style="writing-mode: vertical-rl; text-orientation: mixed;"
      >
        <span class="hero-pencil-square inline-block w-5 h-5 rotate-90"></span>
        <span class="font-bold tracking-wider">NOTES</span>
      </button>
      <button
        phx-click={JS.push("toggle", value: %{what: "branches"})}
        class="absolute left-0 top-[60%] -translate-x-full -translate-y-1/2 bg-blue-600 text-white px-2 py-4 rounded-l-lg shadow-md hover:bg-blue-700 transition-colors focus:outline-none flex flex-col items-center gap-2 z-10"
        style="writing-mode: vertical-rl; text-orientation: mixed;"
      >
        <span class="hero-chat-bubble-left-right inline-block w-5 h-5 rotate-90"></span>
        <span class="font-bold tracking-wider">CONVERSATIONS</span>
      </button>
      <div class={"h-full w-[400px] flex flex-col p-4 border-l border-gray-200 overflow-hidden transition-opacity duration-300 #{if @show_branches, do: "opacity-100", else: "opacity-0 pointer-events-none absolute inset-0"}"}>
        <div class="flex items-center justify-between mb-6 flex-shrink-0">
          <h2 class="text-xl font-bold text-black flex items-center gap-2">
            <span class="hero-chat-bubble-left-right inline-block w-6 h-6"></span> Conversations
          </h2>
          <button
            phx-click={JS.push("toggle", value: %{what: "branches"})}
            class="p-1 hover:bg-gray-100 rounded-full text-gray-500"
            title="Close sidebar"
          >
            <span class="hero-x-mark inline-block w-6 h-6"></span>
          </button>
        </div>
        <div class="flex-1 overflow-y-auto space-y-2 pr-2 custom-scrollbar">
          <.branch_tree nodes={BranchedLLM.BranchedChat.build_tree(@branched_chat)} branched_chat={@branched_chat} />
        </div>
        <div class="mt-4 pt-4 border-t border-gray-100 text-[10px] text-gray-400 italic">
          Branch off any message to start a new thread.
        </div>
      </div>
      <div class={"h-full w-[400px] flex flex-col p-4 border-l border-gray-200 overflow-hidden transition-opacity duration-300 #{if @show_notes, do: "opacity-100", else: "opacity-0 pointer-events-none absolute inset-0"}"}>
        <div class="flex items-center justify-between mb-4 flex-shrink-0">
          <h2 class="text-xl font-bold text-black flex items-center gap-2">
            <span class="hero-pencil-square inline-block w-6 h-6"></span> My Notes
          </h2>
          <button
            phx-click={JS.push("toggle", value: %{what: "notes"})}
            class="p-1 hover:bg-gray-100 rounded-full text-gray-500"
            title="Close notes"
          >
            <span class="hero-x-mark inline-block w-6 h-6"></span>
          </button>
        </div>
        <textarea
          name="notes"
          phx-keyup="update_notes"
          phx-debounce="500"
          class="flex-1 p-4 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-400 bg-[#FFFFFA] text-black resize-none text-base shadow-inner leading-relaxed"
          placeholder="Write down your thoughts, questions, or key takeaways here..."
        ><%= @notes %></textarea>
        <div class="mt-2 text-[10px] text-gray-400 italic text-right flex-shrink-0">
          Notes are saved automatically as you type.
        </div>
      </div>
    </div>
    """
  end

  attr :nodes, :list, required: true
  attr :branched_chat, :map, required: true
  attr :depth, :integer, default: 0

  def branch_tree(assigns) do
    ~H"""
    <%= for node <- @nodes do %>
      <% branch = @branched_chat.branches[node.id] %>
      <div class="flex flex-col">
        <div class="flex items-center">
          <%= if @depth > 0 do %>
            <div class="flex-shrink-0 flex items-center h-full" style={"width: #{@depth * 20}px"}>
              <div class="w-full border-b-2 border-l-2 border-gray-200 rounded-bl-lg h-6 -mt-6"></div>
            </div>
          <% end %>
          <button
            phx-click="switch_branch"
            phx-value-id={node.id}
            class={"flex-1 text-left p-2 my-1 rounded-lg transition-all border #{if node.id == @branched_chat.current_branch_id, do: "bg-blue-50 border-blue-200 text-blue-700 shadow-sm", else: "bg-white border-transparent text-gray-700 hover:bg-gray-50 hover:border-gray-200"}"}
          >
            <div class="flex items-start gap-2">
              <span class={"hero-chat-bubble-bottom-center-text inline-block w-4 h-4 mt-0.5 #{if node.id == @branched_chat.current_branch_id, do: "text-blue-600", else: "text-gray-400"}"}>
              </span>
              <div class="flex-1 min-w-0">
                <div class={"text-xs font-semibold truncate #{if node.id == @branched_chat.current_branch_id, do: "text-blue-800", else: "text-gray-900"}"}>
                  {if branch.name == "", do: "New branch...", else: branch.name}
                </div>
              </div>
            </div>
          </button>
        </div>
        <.branch_tree nodes={node.children} branched_chat={@branched_chat} depth={@depth + 1} />
      </div>
    <% end %>
    """
  end
end
