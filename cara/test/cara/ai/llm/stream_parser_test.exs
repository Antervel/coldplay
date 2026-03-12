defmodule Cara.AI.LLM.StreamParserTest do
  use ExUnit.Case, async: true
  alias Cara.AI.LLM.StreamParser
  alias ReqLLM.StreamChunk
  alias ReqLLM.ToolCall

  describe "consume_until_intent/1" do
    test "handles empty stream" do
      assert {:empty, []} = StreamParser.consume_until_intent([])
    end

    test "handles stream with only meta chunks" do
      meta_chunk = %StreamChunk{type: :meta, metadata: %{some: "data"}}
      stream = [meta_chunk]
      assert {:empty, [^meta_chunk]} = StreamParser.consume_until_intent(stream)
    end

    test "stops at tool call" do
      meta_chunk = %StreamChunk{type: :meta}
      tool_chunk = %StreamChunk{type: :tool_call, name: "calculator"}
      stream = [meta_chunk, tool_chunk, %StreamChunk{type: :content, text: "ignored"}]

      {:tool_call, consumed, remaining} = StreamParser.consume_until_intent(stream)
      assert consumed == [meta_chunk, tool_chunk]
      assert remaining == stream
    end

    test "stops at content chunk" do
      meta_chunk = %StreamChunk{type: :meta}
      content_chunk = %StreamChunk{type: :content, text: "hello"}
      stream = [meta_chunk, content_chunk]

      {:content, consumed, remaining} = StreamParser.consume_until_intent(stream)
      assert consumed == [meta_chunk, content_chunk]
      assert remaining == stream
    end

    test "ignores empty content chunks" do
      empty_content = %StreamChunk{type: :content, text: ""}
      real_content = %StreamChunk{type: :content, text: "real"}
      stream = [empty_content, real_content]

      {:content, consumed, _} = StreamParser.consume_until_intent(stream)
      assert consumed == [empty_content, real_content]
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts simple tool call" do
      chunks = [%StreamChunk{type: :tool_call, name: "test", metadata: %{id: "123"}, arguments: "{\"a\":1}"}]
      [tc] = StreamParser.extract_tool_calls(chunks)
      assert tc.id == "123"
      assert ToolCall.args_json(tc) == "{\"a\":1}"
    end

    test "handles fragments" do
      chunks = [
        %StreamChunk{type: :tool_call, name: "test", metadata: %{id: "123", index: 0}},
        %StreamChunk{type: :meta, metadata: %{tool_call_args: %{index: 0, fragment: "{\"exp"}}},
        %StreamChunk{type: :meta, metadata: %{tool_call_args: %{index: 0, fragment: "ress\":1}"}}}
      ]

      [tc] = StreamParser.extract_tool_calls(chunks)
      assert ToolCall.args_json(tc) == "{\"express\":1}"
    end

    test "handles map arguments" do
      chunks = [%StreamChunk{type: :tool_call, name: "test", metadata: %{id: "123"}, arguments: %{a: 1}}]
      [tc] = StreamParser.extract_tool_calls(chunks)
      assert ToolCall.args_json(tc) == "{\"a\":1}"
    end

    test "handles missing arguments" do
      chunks = [%StreamChunk{type: :tool_call, name: "test", metadata: %{id: "123"}}]
      [tc] = StreamParser.extract_tool_calls(chunks)
      assert ToolCall.args_json(tc) == "{}"
    end

    test "deduplicates by ID" do
      chunks = [
        %StreamChunk{type: :tool_call, name: "test", metadata: %{id: "dup"}, arguments: "{}"},
        %StreamChunk{type: :tool_call, name: "test", metadata: %{id: "dup"}, arguments: "{}"}
      ]

      assert length(StreamParser.extract_tool_calls(chunks)) == 1
    end
  end

  describe "consume_to_text/1" do
    test "reduces stream to text" do
      stream = [%StreamChunk{type: :content, text: "Hello "}, %StreamChunk{type: :content, text: "World"}]
      assert StreamParser.consume_to_text(stream) == "Hello World"
    end

    test "ignores meta chunks" do
      stream = [%StreamChunk{type: :content, text: "Hi"}, %StreamChunk{type: :meta}]
      assert StreamParser.consume_to_text(stream) == "Hi"
    end
  end
end
