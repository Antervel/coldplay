# Refactoring Plan: Cara.AI.Chat

## Objective
The goal of this refactor is to decouple the complex stream parsing logic from the `Cara.AI.Chat` module. This will allow for:
1.  **100% Test Coverage**: The parsing logic contains many edge cases (fragments, argument parsing, duplicate IDs) that are difficult to test via `Cara.AI.Chat`'s public API. Extracting them into a pure functional module will allow direct unit testing.
2.  **Separation of Concerns**: `Cara.AI.Chat` should focus on orchestration (context management, API calls), while the details of interpreting the raw LLM stream should be handled by a specialized component.
3.  **Maintainability**: As new models or providers are added, stream parsing rules may become more complex. Isolating this logic makes it easier to extend without risking the core chat flow.

## Current State
`Cara.AI.Chat` is currently a "God Object" for the chat feature, handling:
-   Context management (`new_context`, `add_user_message`).
-   API execution (`call_llm`).
-   Stream consumption (`consume_until_intent`, `consume_stream_to_text`).
-   Protocol parsing (`extract_tool_calls_from_chunks`, `extract_fragments`, `build_tool_call`).

Coverage is currently stuck at ~91.86% because deeply nested private functions like `extract_fragments` and `build_tool_call` are hard to exercise fully through integration tests involving `Bypass`.

## Proposed Changes

### 1. Extract Stream Parsing Logic
Create a new module, **`Cara.AI.LLM.StreamParser`**, dedicated to processing `ReqLLM` streams.

**Functions to move (and make public):**
-   `consume_until_intent/1`: determining if a stream is content or a tool call.
-   `extract_tool_calls/1` (renamed from `extract_tool_calls_from_chunks`): handling fragment reassembly and argument parsing.
-   `consume_to_text/1` (renamed from `consume_stream_to_text`): converting a stream to a final string.
-   `accumulate_text/2` (renamed from `accumulate_text_chunk`): reducer logic.

### 2. Simplify `Cara.AI.Chat`
The `Cara.AI.Chat` module will retain its public API (`send_message`, `send_message_stream`) but will delegate all stream processing to `StreamParser`.

**Revised `handle_stream_for_tools/1` logic:**
```elixir
defp handle_stream_for_tools(%StreamResponse{stream: stream} = stream_response) do
  case StreamParser.consume_until_intent(stream) do
    {:tool_call, consumed, remaining} ->
      tool_calls = StreamParser.extract_tool_calls(consumed ++ Enum.to_list(remaining))
      {:ok, dummy_stream_response(stream_response), tool_calls}

    {:content, consumed, remaining} ->
      new_stream = Stream.concat(consumed, remaining)
      {:ok, %{stream_response | stream: new_stream}, []}
      
    {:empty, _} ->
      {:ok, stream_response, []}
  end
end
```

### 3. Testing Strategy
-   **`Cara.AI.ChatTest`**: Focus on integration testing using `Bypass`. Verify that messages are sent and contexts are updated. Remove complex edge-case tests that rely on specific chunk fragmentation.
-   **`Cara.AI.LLM.StreamParserTest`**: Create a comprehensive unit test suite.
    -   Test `extract_tool_calls` with various fragmentation patterns (binary splits, map arguments, missing fields).
    -   Test `consume_until_intent` with leading meta chunks, empty streams, and mixed content.
    -   Achieve 100% coverage on this module easily since it requires no mocks or external services.

## Implementation Steps
1.  Create `lib/cara/ai/llm/stream_parser.ex`.
2.  Move the private parsing functions from `Cara.AI.Chat` to the new module.
3.  Write `test/cara/ai/llm/stream_parser_test.exs` covering all edge cases.
4.  Update `Cara.AI.Chat` to alias and use `StreamParser`.
5.  Refactor `test/cara/ai/chat_test.exs` to remove redundant tests covered by the new parser suite.
