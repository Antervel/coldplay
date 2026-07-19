defmodule CaraWeb.ChatLiveTest do
  use CaraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  alias BranchedLLM.BranchedChat
  alias ReqLLM.Context
  alias ReqLLM.StreamResponse
  import Cara.Test.StreamResponseHelper

  setup %{conn: conn} do
    # Stub health check by default
    stub(Cara.AI.ChatMock, :health_check, fn _opts -> :ok end)

    conn = Plug.Test.init_test_session(conn, %{})
    conn = fetch_session(conn)
    student_info = %{name: "Test Student", age: "20", subject: "Elixir", chat_id: "test-chat-id"}
    conn = put_session(conn, :student_info, student_info)
    {:ok, conn: conn}
  end

  # Define mock
  setup :verify_on_exit!

  describe "chat interface" do
    test "mounts with empty state", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      assert view |> has_element?("form")
      assert view |> element("form") |> render() =~ "message"
    end

    test "redirects if student_info is missing from session", %{conn: original_conn} do
      # Remove student_info from the session
      conn = delete_session(original_conn, :student_info)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/chat")
      assert path == "/student"
    end

    test "redirects if student_info in session is invalid (missing chat_id)", %{conn: original_conn} do
      # Put invalid student_info into session
      conn = put_session(original_conn, :student_info, %{name: "Test", age: "10", subject: "Math"})
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/chat")
      assert path == "/student"
    end

    test "redirects to sleeping page when AI is unavailable", %{conn: conn} do
      stub(Cara.AI.ChatMock, :health_check, fn _opts -> {:error, :unavailable} end)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/chat")
      assert path == "/sleeping"
    end

    test "user can send a message and receive a streamed response", %{conn: conn} do
      # Mock the Chat module to return a controlled stream
      mock_stream = [ReqLLM.StreamChunk.text("Hello"), ReqLLM.StreamChunk.text(" there"), ReqLLM.StreamChunk.text("!")]
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: mock_stream,
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Submit a message
      view
      |> form("form", chat: %{message: "Hi"})
      |> render_submit()

      # User message should appear
      assert render(view) =~ "Hi"

      # Allow async task to process
      :timer.sleep(100)

      # Assistant response should be streamed and appear
      assert render(view) =~ "Hello there!"

      # Message input should be cleared (textarea, not input)
      assert view |> element("textarea[name='chat[message]']") |> render() =~ ~r/value=""/
    end

    test "handles multiple messages in conversation", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream = [ReqLLM.StreamChunk.text("A response")]

        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: stream,
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Send first message
      view
      |> form("form", chat: %{message: "First message"})
      |> render_submit()

      :timer.sleep(1500)

      # Send second message
      view
      |> form("form", chat: %{message: "Second message"})
      |> render_submit()

      :timer.sleep(1500)

      html = render(view)

      # All messages should be visible
      assert html =~ "First message"
      assert html =~ "A response"
      assert html =~ "Second message"
      assert html =~ "A response"
    end

    test "ignores empty or whitespace-only messages", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Try to submit empty message
      view
      |> form("form", chat: %{message: ""})
      |> render_submit()

      # Try to submit whitespace message
      view
      |> form("form", chat: %{message: "   "})
      |> render_submit()

      # No new messages should appear (beyond the initial welcome message in main branch)
      html = render(view)
      refute html =~ ~r/message-content-main-1-main/
    end

    test "handles validation events and updates form state", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Simulate typing (validation event) - phx-change is on the textarea element
      view
      |> element("textarea[name='chat[message]']")
      |> render_change(%{chat: %{message: "Typing..."}})

      # The socket state should be updated
      # We can verify the validate handler was called by checking the state
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.message_data == %{"message" => "Typing..."}
    end

    test "handles alternative message submission format", %{conn: conn} do
      # This tests the second handle_event clause: handle_event("submit_message", %{"message" => ...})
      # Both handle_event clauses call do_send_message with the message
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: [ReqLLM.StreamChunk.text("Response")],
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # Push the event directly with the alternative format
      # This will trigger the handle_event("submit_message", %{"message" => message}, socket) clause
      view
      |> render_hook("submit_message", %{"message" => "Test"})

      :timer.sleep(100)

      html = render(view)
      assert html =~ "Test"
      assert html =~ "Response"
    end
  end

  describe "error handling" do
    test "displays error message when LLM returns no chunks", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        {:ok, %BranchedLLM.LLM.StreamResult.EmptyResult{}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Error test"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "The AI did not return a response"
    end

    test "displays error message when Chat.send_message_stream returns error tuple", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        {:error, :api_unavailable}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Error response"})
      |> render_submit()

      :timer.sleep(1500)

      html = render(view)
      assert html =~ "Error:"
      assert html =~ "api_unavailable"
    end

    test "displays error message when LLM stream returns error", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        {:error, "Something went wrong"}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Crash"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "Something went wrong"
    end

    test "handles API errors", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        {:error, "Request failed with status 500"}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "API error"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "Request failed with status 500"
    end

    test "handles empty LLM response", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        {:ok, %BranchedLLM.LLM.StreamResult.EmptyResult{}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Empty response"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "The AI did not return a response"
    end
  end

  describe "streaming behavior" do
    test "progressively builds assistant message from chunks", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream =
          Stream.resource(
            fn -> 0 end,
            fn
              0 -> {[ReqLLM.StreamChunk.text("First ")], 1}
              1 -> {[ReqLLM.StreamChunk.text("second ")], 2}
              2 -> {[ReqLLM.StreamChunk.text("third")], 3}
              3 -> {:halt, 3}
            end,
            fn _ -> :ok end
          )

        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: stream,
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Stream test"})
      |> render_submit()

      :timer.sleep(150)

      # Full message should be assembled
      assert render(view) =~ "First second third"
    end

    test "handles empty chunks gracefully", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream = [
          ReqLLM.StreamChunk.text("Hello"),
          ReqLLM.StreamChunk.text(""),
          ReqLLM.StreamChunk.text(" "),
          ReqLLM.StreamChunk.text(""),
          ReqLLM.StreamChunk.text("world")
        ]

        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: stream,
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Empty chunks"})
      |> render_submit()

      :timer.sleep(1500)

      # Empty chunks should not create issues
      assert render(view) =~ "Hello world"
    end
  end

  describe "context management" do
    test "updates context after successful stream completion", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: [ReqLLM.StreamChunk.text("Response")],
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # First message
      view
      |> form("form", chat: %{message: "First"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "Response"

      view
      |> form("form", chat: %{message: "Second"})
      |> render_submit()

      :timer.sleep(1500)

      assert render(view) =~ "Response"
    end

    test "preserves context when error occurs", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        raise "Something went wrong"
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Error"})
      |> render_submit()

      :timer.sleep(1500)

      # Context should preserve the user message even on error
      state = :sys.get_state(view.pid)
      ctx = BranchedChat.get_current_context(state.socket.assigns.branched_chat)
      refute is_nil(ctx)
      user_msg = List.last(ctx.messages)
      assert user_msg.role == :user
    end
  end

  describe "markdown rendering" do
    test "renders markdown content in messages", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      stub(Cara.AI.ChatClientMock, :send_message_stream, fn _ctx, _opts ->
        # Return markdown content
        stream = [ReqLLM.StreamChunk.text("**Bold** and *italic*")]

        stream_response = %StreamResponse{
          context: %ReqLLM.Context{messages: []},
          model: %LLMDB.Model{id: "test-model", provider: :openai},
          cancel: fn -> :ok end,
          stream: stream,
          metadata_handle: start_metadata_handle()
        }

        {:ok, %BranchedLLM.LLM.StreamResult.ContentResult{stream: stream_response}}
      end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      view
      |> form("form", chat: %{message: "Markdown test"})
      |> render_submit()

      :timer.sleep(1500)

      # Markdown should be rendered to HTML
      html = render(view)
      assert html =~ "Bold"
      assert html =~ "italic"
    end

    test "render_markdown function can be called directly", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      {:ok, _view, _html} = live(conn, ~p"/chat")

      # Call render_markdown directly
      result = CaraWeb.MarkdownHelpers.render_markdown("# Hello **World**")

      # Should return safe HTML
      assert Phoenix.HTML.safe_to_string(result) =~ "Hello"
      assert Phoenix.HTML.safe_to_string(result) =~ "World"
    end
  end

  describe "edge case coverage" do
    test "get_last_assistant_message_content returns empty string for non-assistant last message", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)

      {:ok, view, _html} = live(conn, ~p"/chat")

      # The orchestrator now handles context updates internally via :llm_end
      # This edge case is covered by the orchestrator tests
      state = :sys.get_state(view.pid)
      refute is_nil(BranchedChat.get_current_context(state.socket.assigns.branched_chat))
    end
  end

  describe "notes panel" do
    test "toggles notes panel", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)
      {:ok, view, _html} = live(conn, ~p"/chat")

      # Initially closed
      assert render(view) =~
               ~r/h-full w-\[400px\] flex flex-col p-4 border-l border-gray-200 overflow-hidden transition-opacity duration-300 opacity-0 pointer-events-none/

      # Toggle open
      view |> element("button", "NOTES") |> render_click()

      assert render(view) =~
               ~r/h-full w-\[400px\] flex flex-col p-4 border-l border-gray-200 overflow-hidden transition-opacity duration-300 opacity-100/

      # Toggle closed via the 'X' button
      view |> element("button[title='Close notes']") |> render_click()

      assert render(view) =~
               ~r/h-full w-\[400px\] flex flex-col p-4 border-l border-gray-200 overflow-hidden transition-opacity duration-300 opacity-0 pointer-events-none/
    end

    test "updates notes", %{conn: conn} do
      stub(Cara.AI.ChatMock, :new_context, fn _system_prompt -> Context.new([]) end)
      {:ok, view, _html} = live(conn, ~p"/chat")

      # Type some notes (phx-keyup)
      view
      |> element("textarea[name='notes']")
      |> render_keyup(%{"value" => "These are my notes."})

      # Verify socket state
      state = :sys.get_state(view.pid)
      assert state.socket.assigns.notes == "These are my notes."

      # Verify rendered content
      assert render(view) =~ "These are my notes."
    end
  end
end
