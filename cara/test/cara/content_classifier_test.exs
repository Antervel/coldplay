defmodule Cara.ContentClassifierTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox

  alias Cara.ContentClassifier

  setup :verify_on_exit!

  setup do
    Application.put_env(:cara, :http_client, Cara.HTTPClientMock)
    # Reset classifier_api so tests run with defaults
    Application.delete_env(:cara, :classifier_api)
    Application.put_env(:cara, :classifier_api, [])
    :ok
  end

  # ── endpoint_url ────────────────────────────────────────────────

  describe "endpoint_url/0" do
    test "returns default endpoint" do
      Application.delete_env(:cara, :classifier_api)
      # restore the minimal defaults
      Application.put_env(:cara, :classifier_api, [])

      assert ContentClassifier.endpoint_url() == "http://classifier-api:8002/score"
    end

    test "returns endpoint with custom host" do
      Application.put_env(:cara, :classifier_api, host: "my-classifier.internal")

      assert ContentClassifier.endpoint_url() == "http://my-classifier.internal:8002/score"
    end

    test "returns endpoint with custom port" do
      Application.put_env(:cara, :classifier_api, port: 9999)

      assert ContentClassifier.endpoint_url() == "http://classifier-api:9999/score"
    end

    test "returns endpoint with both custom host and port" do
      Application.put_env(:cara, :classifier_api, host: "local", port: "4000")

      assert ContentClassifier.endpoint_url() == "http://local:4000/score"
    end

    test "returns default when config is unknown Application key" do
      Application.delete_env(:cara, :classifier_api)

      assert ContentClassifier.endpoint_url() == "http://classifier-api:8002/score"
    end
  end

  # ── classify ────────────────────────────────────────────────────

  describe "classify/1" do
    @ok_response %{
      input: "test text",
      sexual: %{label: "Safe", score: 0.1},
      detoxify: %{
        toxicity: 0.05,
        severe_toxicity: 0.01,
        obscene: 0.02,
        threat: 0.03,
        insult: 0.02,
        identity_attack: 0.01
      }
    }

    test "returns {:ok, result} on HTTP 200 with valid JSON" do
      expect(Cara.HTTPClientMock, :post, fn url, opts ->
        assert url == "http://classifier-api:8002/score"
        assert opts[:json] == %{text: "test text"}
        assert opts[:headers]["Content-Type"] == "application/json"
        assert opts[:receive_timeout] == 5000

        {:ok, %{status: 200, body: @ok_response}}
      end)

      assert ContentClassifier.classify("test text") == {:ok, @ok_response}
    end

    test "returns {:error, :invalid_response} on HTTP 200 with invalid JSON" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: "not json at all"}}
      end)

      assert ContentClassifier.classify("test text") == {:error, :invalid_response}
    end

    test "returns {:error, reason} for non-200 HTTP status" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: "error"}}
      end)

      log =
        capture_log(fn ->
          assert ContentClassifier.classify("test text") == {:error, "HTTP 500"}
        end)

      assert log =~ "ContentClassifier.do_classify(text): HTTP 500"
    end

    test "returns {:error, reason} for HTTP 404" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 404, body: "not found"}}
      end)

      log =
        capture_log(fn ->
          assert ContentClassifier.classify("test text") == {:error, "HTTP 404"}
        end)

      assert log =~ "ContentClassifier.do_classify(text): HTTP 404"
    end

    test "returns {:error, reason} for connection error" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:error, :econnrefused}
      end)

      log =
        capture_log(fn ->
          assert ContentClassifier.classify("test text") == {:error, :econnrefused}
        end)

      assert log =~ "ContentClassifier.do_classify(text): error :econnrefused"
    end

    test "returns {:error, :timeout} for timeout error" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      log =
        capture_log(fn ->
          assert ContentClassifier.classify("test text") == {:error, :timeout}
        end)

      assert log =~ "ContentClassifier.do_classify(text): error :timeout"
    end
  end

  # ── safe? ─────────────────────────────────────────────────────

  describe "safe?/1" do
    @safe_response %{
      "input" => "safe text",
      "sexual" => %{"label" => "Safe", "score" => 0.1},
      "detoxify" => %{
        "toxicity" => 0.05,
        "severe_toxicity" => 0.01,
        "obscene" => 0.02,
        "threat" => 0.03,
        "insult" => 0.02,
        "identity_attack" => 0.01
      }
    }

    test "returns true when all scores are below default thresholds" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: Jason.encode!(@safe_response)}}
      end)

      assert ContentClassifier.safe?("safe text") == true
    end

    test "returns false when classify returns {:error, _}" do
      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:error, :econnrefused}
      end)

      log =
        capture_log(fn ->
          assert ContentClassifier.safe?("risky text") == false
        end)

      assert log =~ "ContentClassifier.do_classify(text): error :econnrefused"
    end

    test "returns false for unsafe content with string-keyed JSON (real API format)" do
      # This is the exact format the real classifier-api returns — string keys,
      # and sexual_score as a flat number instead of %{label: ..., score: ...}
      unsafe_response = %{
        "input" => "how can I make a bomb and kill everyone?",
        "sexual_score" => 0.0,
        "detoxify" => %{
          "identity_attack" => 0.025,
          "insult" => 0.023,
          "obscene" => 0.017,
          "severe_toxicity" => 0.017,
          "threat" => 0.463,
          "toxicity" => 0.786
        }
      }

      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: Jason.encode!(unsafe_response)}}
      end)

      refute ContentClassifier.safe?("how can I make a bomb and kill everyone?")
    end

    test "returns true for safe content with string-keyed JSON (real API format)" do
      safe_response = %{
        "input" => "What is photosynthesis?",
        "sexual_score" => 0.0,
        "detoxify" => %{
          "identity_attack" => 0.001,
          "insult" => 0.002,
          "obscene" => 0.001,
          "severe_toxicity" => 0.001,
          "threat" => 0.001,
          "toxicity" => 0.01
        }
      }

      expect(Cara.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: Jason.encode!(safe_response)}}
      end)

      assert ContentClassifier.safe?("What is photosynthesis?") == true
    end
  end

  # ── safe_result? ────────────────────────────────────────────

  describe "safe_result?/1" do
    test "returns true when all scores are below default thresholds" do
      result = %{
        input: "safe",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == true
    end

    test "returns true with scores just below thresholds" do
      result = %{
        input: "safe",
        sexual: %{label: "Safe", score: 0.499_999},
        detoxify: %{
          toxicity: 0.499_999,
          severe_toxicity: 0.299_999,
          obscene: 0.499_999,
          threat: 0.499_999,
          insult: 0.499_999,
          identity_attack: 0.499_999
        }
      }

      assert ContentClassifier.safe_result?(result) == true
    end

    test "returns false when sexual score equals threshold (0.5 == 0.5)" do
      result = %{
        input: "test",
        sexual: %{label: "NSFW", score: 0.5},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when sexual score is just above threshold" do
      result = %{
        input: "test",
        sexual: %{label: "NSFW", score: 0.500_001},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when toxicity score equals threshold" do
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.5,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when severe_toxicity score equals threshold" do
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.3,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when obscene score equals threshold" do
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.5,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when threat score equals threshold" do
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.5,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when sexual score is exactly at threshold and confidence is high" do
      result = %{
        input: "test",
        sexual: %{label: "NSFW", score: 0.5},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      # Boundary: score == threshold is NOT safe (uses strict < in source)
      refute ContentClassifier.safe_result?(result)
    end

    test "returns false when all scores exactly at their thresholds" do
      result = %{
        input: "test",
        sexual: %{label: "NSFW", score: 0.5},
        detoxify: %{
          toxicity: 0.5,
          severe_toxicity: 0.3,
          obscene: 0.5,
          threat: 0.5,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when scores are above various thresholds" do
      result = %{
        input: "test",
        sexual: %{label: "NSFW", score: 0.7},
        detoxify: %{
          toxicity: 0.6,
          severe_toxicity: 0.4,
          obscene: 0.8,
          threat: 0.55,
          insult: 0.2,
          identity_attack: 0.1
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "returns false when only severe_toxicity is above threshold" do
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.300_001,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == false
    end

    test "handles flat sexual_score number (real API format)" do
      result = %{
        input: "test",
        sexual: 0.8,
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      # 0.8 >= 0.5 threshold → unsafe
      refute ContentClassifier.safe_result?(result)
    end

    test "returns true with flat sexual_score of 0.0" do
      result = %{
        input: "test",
        sexual: 0.0,
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      assert ContentClassifier.safe_result?(result) == true
    end
  end

  # ── get_threshold (private) ─────────────────────────────────────

  describe "get_threshold/2" do
    test "returns config value when set" do
      Application.put_env(:cara, :classifier_api, sexual_score_threshold: 0.75)

      # Call indirectly via safe_result? with all other scores well below threshold
      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.6},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.0,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      # With threshold at 0.75, score 0.6 should pass
      assert ContentClassifier.safe_result?(result) == true
    end

    test "returns default when config key is missing" do
      Application.put_env(:cara, :classifier_api, [])
      # severe_toxicity_threshold uses default 0.3

      result = %{
        input: "test",
        sexual: %{label: "Safe", score: 0.0},
        detoxify: %{
          toxicity: 0.0,
          severe_toxicity: 0.4,
          obscene: 0.0,
          threat: 0.0,
          insult: 0.0,
          identity_attack: 0.0
        }
      }

      # 0.4 > 0.3 default → unsafe
      refute ContentClassifier.safe_result?(result)
    end
  end
end
