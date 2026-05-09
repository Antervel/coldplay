defmodule Cara.AI.GuardTest do
  use ExUnit.Case, async: true

  alias Cara.AI.Guard

  # Ensure clean default guard config before each test
  setup do
    Application.put_env(:cara, :guard,
      enabled: false,
      model: "llama-guard3:1b",
      apply_to: :all,
      send_history: false,
      violation_messages: %{
        s1: "Violent Crimes",
        s2: "Non-Violent Crimes",
        s3: "Sex-Related Crimes",
        s4: "Child Sexual Exploitation",
        s5: "Defamation",
        s6: "Specialized Advice",
        s7: "Privacy",
        s8: "Intellectual Property",
        s9: "Indiscriminate Weapons",
        s10: "Hate",
        s11: "Suicide & Self-Harm",
        s12: "Sorry, I can't answer about this topic. What else do you want to know about?",
        s13: "Elections"
      }
    )

    on_exit(fn ->
      Application.delete_env(:cara, :guard)
      Application.delete_env(:req_llm, :openai)
    end)

    :ok
  end

  describe "get_violation_message/1" do
    test "returns message for known violation codes" do
      assert Guard.get_violation_message("S1") == "Violent Crimes"
      assert Guard.get_violation_message("S2") == "Non-Violent Crimes"
      assert Guard.get_violation_message("S3") == "Sex-Related Crimes"
      assert Guard.get_violation_message("S4") == "Child Sexual Exploitation"
      assert Guard.get_violation_message("S5") == "Defamation"
      assert Guard.get_violation_message("S6") == "Specialized Advice"
      assert Guard.get_violation_message("S7") == "Privacy"
      assert Guard.get_violation_message("S8") == "Intellectual Property"
      assert Guard.get_violation_message("S9") == "Indiscriminate Weapons"
      assert Guard.get_violation_message("S10") == "Hate"
      assert Guard.get_violation_message("S11") == "Suicide & Self-Harm"

      assert Guard.get_violation_message("S12") ==
               "Sorry, I can't answer about this topic. What else do you want to know about?"

      assert Guard.get_violation_message("S13") == "Elections"
    end

    test "returns default message for unknown codes" do
      assert Guard.get_violation_message("S99") ==
               "Sorry, I can't answer about this topic. What else do you want to know about?"

      assert Guard.get_violation_message("UNKNOWN") ==
               "Sorry, I can't answer about this topic. What else do you want to know about?"
    end

    test "is case-insensitive" do
      assert Guard.get_violation_message("s1") == "Violent Crimes"

      assert Guard.get_violation_message("s12") ==
               "Sorry, I can't answer about this topic. What else do you want to know about?"
    end
  end

  describe "check/2 when disabled" do
    test "returns :safe when guard is disabled" do
      # Ensure guard is disabled (default from setup)
      Application.put_env(:cara, :guard, enabled: false)

      assert Guard.check("harmful content") == :safe
    end

    test "returns :safe when no guard config exists" do
      Application.delete_env(:cara, :guard)

      assert Guard.check("anything") == :safe
    end
  end

  describe "check/2 when enabled" do
    setup do
      bypass = Bypass.open()

      # Configure guard to be enabled and use the bypass URL
      Application.put_env(:req_llm, :openai,
        base_url: "http://localhost:#{bypass.port}/v1",
        api_key: "test-key"
      )

      Application.put_env(:cara, :guard,
        enabled: true,
        model: "llama-guard3:1b",
        apply_to: :all,
        send_history: false,
        violation_messages: %{
          s1: "Violent Crimes",
          s12: "Sorry, I can't answer about this topic. What else do you want to know about?"
        }
      )

      {:ok, bypass: bypass}
    end

    test "returns :safe for safe content", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({
          "id": "test-id",
          "object": "chat.completion",
          "created": 1234567890,
          "model": "llama-guard3:1b",
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "content": "safe"
              },
              "finish_reason": "stop"
            }
          ]
        }))
      end)

      assert Guard.check("Hello, how are you?") == :safe
    end

    test "returns {:unsafe, message} for unsafe content", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        response =
          Jason.encode!(%{
            "id" => "test-id",
            "object" => "chat.completion",
            "created" => 1_234_567_890,
            "model" => "llama-guard3:1b",
            "choices" => [
              %{
                "index" => 0,
                "message" => %{
                  "role" => "assistant",
                  "content" => "unsafe\nS1"
                },
                "finish_reason" => "stop"
              }
            ]
          })

        Plug.Conn.resp(conn, 200, response)
      end)

      assert Guard.check("harmful content") == {:unsafe, "Violent Crimes"}
    end

    test "handles non-200 responses gracefully", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      assert Guard.check("test") == :safe
    end

    test "handles errors gracefully", %{bypass: bypass} do
      Bypass.down(bypass)

      assert Guard.check("test") == :safe
    end

    test "handles empty choices", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({
          "id": "test-id",
          "object": "chat.completion",
          "created": 1234567890,
          "model": "llama-guard3:1b",
          "choices": []
        }))
      end)

      assert Guard.check("test") == :safe
    end

    test "handles malformed responses gracefully", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 200, "not valid json")
      end)

      # Since the response is not valid JSON, the Req library will handle it,
      # but our parser gets the raw body. In practice, this may fail.
      # We just want to ensure it doesn't crash.
      result = Guard.check("test")
      assert result == :safe or match?({:unsafe, _}, result)
    end
  end
end
