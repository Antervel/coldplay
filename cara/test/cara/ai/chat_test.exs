defmodule Cara.AI.ChatTest do
  use ExUnit.Case, async: true

  alias Cara.AI.Chat
  alias Cara.AI.CLI
  alias Cara.AI.Tools.Calculator
  alias ReqLLM.Context

  describe "new_context/0" do
    test "creates a context with default system prompt" do
      context = Chat.new_context("Test system prompt")

      assert %Context{} = context
      assert length(context.messages) == 1
      assert hd(context.messages).role == :system
    end
  end

  describe "new_context/1" do
    test "creates a context with custom system prompt" do
      custom_prompt = "You are a helpful coding assistant."
      context = Chat.new_context(custom_prompt)

      assert %Context{} = context
      assert length(context.messages) == 1

      message = hd(context.messages)
      assert message.role == :system
      assert hd(message.content).text == custom_prompt
    end
  end

  describe "get_history/1" do
    test "returns the list of messages from context" do
      context = Chat.new_context("Test system prompt")
      history = Chat.get_history(context)

      assert is_list(history)
      assert length(history) == 1
    end

    test "returns all messages including user and assistant messages" do
      context =
        Chat.new_context("Test system prompt")
        |> Context.append(ReqLLM.Context.user("Hello"))
        |> Context.append(ReqLLM.Context.assistant("Hi there!"))

      history = Chat.get_history(context)

      assert length(history) == 3
      assert Enum.at(history, 0).role == :system
      assert Enum.at(history, 1).role == :user
      assert Enum.at(history, 2).role == :assistant
    end
  end

  describe "reset_context/1" do
    test "keeps only system messages" do
      context =
        Chat.new_context("Test system prompt")
        |> Context.append(ReqLLM.Context.user("Hello"))
        |> Context.append(ReqLLM.Context.assistant("Hi there!"))
        |> Context.append(ReqLLM.Context.user("How are you?"))

      assert length(context.messages) == 4

      reset_context = Chat.reset_context(context)

      assert length(reset_context.messages) == 1
      assert hd(reset_context.messages).role == :system
    end

    test "preserves multiple system messages if present" do
      context =
        Chat.new_context("Test system prompt")
        |> Context.append(ReqLLM.Context.system("Additional instruction"))
        |> Context.append(ReqLLM.Context.user("Hello"))

      assert length(context.messages) == 3

      reset_context = Chat.reset_context(context)

      assert length(reset_context.messages) == 2
      assert Enum.all?(reset_context.messages, fn msg -> msg.role == :system end)
    end
  end

  describe "send_message/3" do
    setup do
      bypass = Bypass.open()

      # Configure ReqLLM to use bypass URL - note the path is included in base_url
      Application.put_env(:req_llm, :openrouter,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test-key"
      )

      System.put_env("OPENROUTER_API_KEY", "test-key")

      on_exit(fn ->
        Application.delete_env(:req_llm, :openrouter)
      end)

      {:ok, bypass: bypass}
    end

    test "sends a message and returns response with updated context", %{bypass: bypass} do
      # OpenRouter uses /chat/completions endpoint
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Hello! How can I help you?"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")
      {:ok, response, new_context} = Chat.send_message("Hello", context, model: "openrouter:test-model")

      assert is_binary(response)
      assert response =~ "Hello"
      assert %Context{} = new_context
      # system + user + assistant
      assert length(new_context.messages) == 3
    end

    test "includes user message in context", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify user message is in the request
        # The content is a simple string, not a list of parts
        assert Enum.any?(request["messages"], fn msg ->
                 msg["role"] == "user" && msg["content"] == "Test message"
               end)

        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Response"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")
      {:ok, _response, new_context} = Chat.send_message("Test message", context, model: "openrouter:test-model")

      user_messages = Enum.filter(new_context.messages, fn msg -> msg.role == :user end)
      assert match?([_], user_messages)
      assert hd(hd(user_messages).content).text == "Test message"
    end

    test "sends a message using the default model when no options are provided", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => Chat.default_model(),
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Default response"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")
      {:ok, response, new_context} = Chat.send_message("Hello", context)

      assert is_binary(response)
      assert response =~ "Default response"
      assert %Context{} = new_context
      assert length(new_context.messages) == 3
    end
  end

  describe "send_message_stream/3" do
    setup do
      bypass = Bypass.open()

      Application.put_env(:req_llm, :openrouter,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test-key"
      )

      System.put_env("OPENROUTER_API_KEY", "test-key")

      on_exit(fn ->
        Application.delete_env(:req_llm, :openrouter)
      end)

      {:ok, bypass: bypass}
    end

    test "returns a stream and context builder function", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Streamed response"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")

      {:ok, stream, context_builder, _tool_calls} =
        Chat.send_message_stream("Hello", context, model: "openrouter:test-model")

      assert is_function(context_builder, 1)

      # Consume the stream
      chunks = Enum.to_list(stream)
      assert not Enum.empty?(chunks)
      assert Enum.all?(chunks, &is_binary/1)
    end

    test "send_message_stream works with default options", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Response"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      # Call without passing opts to trigger the 2-arity version
      context = Chat.new_context("Test system prompt")
      {:ok, stream, _context_builder, _tool_calls} = Chat.send_message_stream("Hello", context)

      chunks = Enum.to_list(stream)
      assert is_list(chunks)
    end

    test "context builder creates context with assistant message", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        response = %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{"content" => "Test response"},
              "finish_reason" => nil
            }
          ]
        }

        {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")

      {:ok, stream, context_builder, _tool_calls} =
        Chat.send_message_stream("Hello", context, model: "openrouter:test-model")

      # Consume the stream
      full_text = Enum.join(stream, "")

      # Build the final context
      final_context = context_builder.(full_text)

      assert %Context{} = final_context
      # system + user + assistant
      assert length(final_context.messages) == 3

      assistant_messages = Enum.filter(final_context.messages, fn msg -> msg.role == :assistant end)
      assert length(assistant_messages) == 1
      assert hd(hd(assistant_messages).content).text == full_text
    end

    test "stream yields text chunks in order", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} = send_chunk(conn, %{"choices" => [%{"index" => 0, "delta" => %{"content" => "First "}}]})
        {:ok, conn} = send_chunk(conn, %{"choices" => [%{"index" => 0, "delta" => %{"content" => "Second "}}]})
        {:ok, conn} = send_chunk(conn, %{"choices" => [%{"index" => 0, "delta" => %{"content" => "Third"}}]})
        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      context = Chat.new_context("Test system prompt")

      {:ok, stream, _context_builder, _tool_calls} =
        Chat.send_message_stream("Hello", context, model: "openrouter:test-model")

      chunks = Enum.to_list(stream)
      full_text = Enum.join(chunks, "")

      assert full_text == "First Second Third"
    end
  end

  describe "send_message_stream/3 with tools - no tool calls" do
    setup do
      bypass = Bypass.open()

      Application.put_env(:req_llm, :openrouter,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test-key"
      )

      System.put_env("OPENROUTER_API_KEY", "test-key")

      on_exit(fn ->
        Application.delete_env(:req_llm, :openrouter)
      end)

      {:ok, bypass: bypass}
    end

    test "handles tools provided but no tool calls made", %{bypass: bypass} do
      # First call to generate_text returns no tool calls
      Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Check if this is a streaming request or not
        is_streaming = Map.get(request, "stream", false)

        if is_streaming do
          # Second call - streaming response
          conn = Plug.Conn.send_chunked(conn, 200)

          response = %{
            "id" => "test-id",
            "object" => "chat.completion.chunk",
            "created" => 1_234_567_890,
            "model" => "test-model",
            "choices" => [
              %{
                "index" => 0,
                "delta" => %{"content" => "No tools needed"},
                "finish_reason" => nil
              }
            ]
          }

          {:ok, conn} = Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
          {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
          conn
        else
          # First call - non-streaming response without tool calls
          response = %{
            "id" => "test-id",
            "object" => "chat.completion",
            "created" => 1_234_567_890,
            "model" => "test-model",
            "choices" => [
              %{
                "index" => 0,
                "message" => %{
                  "role" => "assistant",
                  "content" => "No tools needed"
                },
                "finish_reason" => "stop"
              }
            ]
          }

          Plug.Conn.send_resp(conn, 200, Jason.encode!(response))
        end
      end)

      context = Chat.new_context("Test system prompt")
      calculator_tool = Calculator.calculator_tool()

      {:ok, stream, _context_builder, tool_calls} =
        Chat.send_message_stream("What is 2+2?", context,
          model: "openrouter:test-model",
          tools: [calculator_tool]
        )

      chunks = Enum.to_list(stream)
      assert is_list(chunks)
      assert tool_calls == []
    end
  end

  describe "send_message_stream/3 with tools - tool calls made" do
    setup do
      bypass = Bypass.open()

      Application.put_env(:req_llm, :openrouter,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test-key"
      )

      System.put_env("OPENROUTER_API_KEY", "test-key")

      on_exit(fn ->
        Application.delete_env(:req_llm, :openrouter)
      end)

      {:ok, bypass: bypass}
    end

    test "handles tools provided and tool calls made", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        # Non-streaming response with tool calls
        response = %{
          "id" => "test-id",
          "object" => "chat.completion",
          "created" => 1_234_567_890,
          "model" => "test-model",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  %{
                    "id" => "call_123",
                    "type" => "function",
                    "function" => %{
                      "name" => "calculator",
                      "arguments" => Jason.encode!(%{"expression" => "2+2"})
                    }
                  }
                ]
              },
              "finish_reason" => "tool_calls"
            }
          ]
        }

        Plug.Conn.send_resp(conn, 200, Jason.encode!(response))
      end)

      context = Chat.new_context("Test system prompt")
      calculator_tool = Calculator.calculator_tool()

      {:ok, _stream, _context_builder, tool_calls} =
        Chat.send_message_stream("Calculate 2+2", context,
          model: "openrouter:test-model",
          tools: [calculator_tool]
        )

      assert length(tool_calls) > 0
    end
  end

  describe "execute_tool/2" do
    test "executes calculator tool successfully" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "2+2"}

      assert {:ok, 4} = Chat.execute_tool(calculator_tool, args)
    end

    test "executes calculator tool with atom keys" do
      calculator_tool = Calculator.calculator_tool()
      args = %{expression: "(5*5)+10"}

      assert {:ok, 35} = Chat.execute_tool(calculator_tool, args)
    end

    test "returns error for invalid expression" do
      calculator_tool = Calculator.calculator_tool()
      args = %{"expression" => "invalid syntax here"}

      assert {:error, error} = Chat.execute_tool(calculator_tool, args)
      # The error is a struct with an error field
      assert is_struct(error) or is_binary(error)
    end

    test "returns error for missing expression parameter" do
      calculator_tool = Calculator.calculator_tool()
      args = %{}

      assert {:error, error} = Chat.execute_tool(calculator_tool, args)
      # ReqLLM returns a validation error struct, not a simple string
      assert error.reason =~ "required :expression option not found" or
               error == "Missing 'expression' parameter"
    end
  end

  describe "start/1" do
    test "returns error when API key is not set" do
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      # Can't easily test interactive loop, but we can test the API key validation
      assert {:error, :missing_api_key} = CLI.start()

      if original_key do
        System.put_env("OPENROUTER_API_KEY", original_key)
      end
    end
  end

  # Helper function to send chunks
  defp send_chunk(conn, data) do
    response =
      Map.merge(
        %{
          "id" => "test-id",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "test-model"
        },
        data
      )

    Plug.Conn.chunk(conn, "data: #{Jason.encode!(response)}\n\n")
  end

  describe "default_model/0" do
    test "returns the default model string" do
      assert Chat.default_model() =~ "openrouter:"
    end
  end
end
