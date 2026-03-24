# How Tools are Implemented in Cara

This document explains the architecture for integrating external tools with the Large Language Model (LLM) in the Cara application. It also provides a step-by-step guide for adding new tools in the future.

## 1. Introduction

Tools allow the LLM to perform specific actions or access external information that is beyond its intrinsic knowledge. In Cara, tools enable the AI companion to, for example, perform calculations, retrieve data from a database, or interact with APIs. The system employs a "Reason-Act-Answer" loop, where the LLM can decide to use a tool based on the user's query, execute it, and then incorporate the tool's result into its final response.

## 2. Core Components for Tool Support

Tool support in Cara relies on several key modules and the `req_llm` library:

*   **`req_llm` library (`ReqLLM.Tool`, `ReqLLM.ToolCall`, `ReqLLM.Context`):**
    *   `ReqLLM.Tool`: A struct used to define a tool's name, description, parameter schema, and the Elixir callback function that executes the tool's logic.
    *   `ReqLLM.ToolCall`: A struct representing an LLM's request to use a specific tool with certain arguments.
    *   `ReqLLM.Context`: Manages the conversation history, including system messages, user messages, assistant messages, and most importantly for tools, `assistant_tool_calls` and `tool_result` messages.

*   **`Cara.AI.Chat` (`lib/cara/ai/chat.ex`):**
    *   This module serves as the primary interface for interacting with LLM APIs via `req_llm`.
    *   It's responsible for making calls to the LLM, passing along the conversation context and any available tools.
    *   Its `call_llm/3` private function uses `ReqLLM.stream_text` and a peeking mechanism (`handle_stream_for_tools`) to detect if the LLM is initiating a tool call or responding with text.
    *   It also provides the `execute_tool/2` function, which wraps `ReqLLM.Tool.execute/2` to run a tool's callback.

*   **`Cara.AI.ChatBehaviour` (`lib/cara/ai/chat_behaviour.ex`):**
    *   Defines the contract for any chat module in Cara.
    *   It includes `@callback` definitions for functions like `send_message_stream/3` (which supports passing tools) and `execute_tool/2`, ensuring consistency across different LLM implementations or mocks.

*   **`Cara.AI.ToolHandler` (`lib/cara/ai/tool_handler.ex`):**
    *   This module contains pure functions responsible for processing tool calls and managing context updates.
    *   It iterates through requested tool calls, finds the corresponding tool, executes it using the chat module's `execute_tool/2`, and appends the results (or errors) to the conversation context.

*   **`CaraWeb.ChatLive` (`lib/cara_web/live/chat_live.ex`):**
    *   This Phoenix LiveView module orchestrates the entire chat interaction, including the tool execution loop.
    *   It loads available tools using `Cara.AI.Tools.load_tools()` in its `mount/3` function.
    *   Its `process_llm_request` function manages the "Reason-Act-Answer" loop:
        1.  **Reason:** Calls `Cara.AI.Chat.send_message_stream` to send the user's message and available tools to the LLM.
        2.  **Act:** If tool calls are requested, `handle_llm_stream_response` delegates to `handle_tool_call_execution`, which adds the `assistant` message with tool calls to the context and uses `Cara.AI.ToolHandler` to execute them.
        3.  **Answer:** With the tool results now in the context, `process_llm_request` is called recursively for a final response.

*   **Specific Tool Modules (e.g., `Cara.AI.Tools.Calculator`, `Cara.AI.Tools.Wikipedia`):**
    *   These modules define the actual tools. Each module typically exposes functions (e.g., `calculator_tool/0`, `wikipedia_search/0`) that return a `ReqLLM.Tool` struct.

## 3. Tool Execution Flow (Reason-Act-Answer Loop)

When a user interacts with the AI and their query requires a tool, the following sequence of events occurs:

1.  **User Input:** The user types a message (e.g., "What is 123 * 45?").
2.  **Initial LLM Call (`CaraWeb.ChatLive.process_llm_request` -> `Cara.AI.Chat.send_message_stream`):**
    *   The system sends the current conversation context along with the list of available tools to the LLM.
    *   `Cara.AI.Chat.call_llm` uses `ReqLLM.stream_text` and peeks at the start of the stream to determine the LLM's intent.
3.  **Tool Call Detected:**
    *   If the LLM decides to use a tool, `call_llm` consumes the stream to extract all `ReqLLM.ToolCall` structs and returns them.
4.  **Orchestration in `CaraWeb.ChatLive`:**
    *   `handle_llm_stream_response` detects the tool calls and triggers `handle_tool_call_execution`.
    *   An `assistant` message containing the `tool_calls` is appended to the conversation context.
5.  **Tool Execution (`Cara.AI.ToolHandler.handle_tool_calls`):**
    *   `Cara.AI.ToolHandler.handle_tool_calls` iterates through each `ReqLLM.ToolCall`.
    *   For each tool call, it finds the corresponding `ReqLLM.Tool` and executes its `callback` via `chat_module.execute_tool/2`.
    *   The result (or error) is appended to the context as a `tool` message.
6.  **Second LLM Call (Recursion):**
    *   `process_llm_request` is called recursively with the updated context containing the tool results.
7.  **Final Answer:**
    *   The LLM generates a natural language response based on the tool results, which is streamed to the UI.

## 4. HOWTO: Adding a New Tool

Follow these steps to add a new tool to the Cara application:

### Step 1: Define the Tool Module

Create a new `.ex` file for your tool definition in `lib/cara/ai/tools/`.

**Example: `lib/cara/ai/tools/my_new_tool.ex`**

```elixir
defmodule Cara.AI.Tools.MyNewTool do
  alias ReqLLM.Tool

  def my_new_tool() do
    Tool.new!(
      name: "my_new_tool",
      description: "Description of what the tool does.",
      parameter_schema: [
        param1: [type: :string, required: true, doc: "Description"]
      ],
      callback: fn args ->
        # Implement logic
        {:ok, "Result"}
      end
    )
  end
end
```

### Step 2: Register the Tool in `Cara.AI.Tools`

Modify `lib/cara/ai/tools.ex` to include your new tool in the `load_tools/0` function.

1.  **Add to `load_tools` default list or configuration.**
2.  **Add a clause to `instantiate_tool/1`:**
    ```elixir
    defp instantiate_tool(:my_new_tool), do: MyNewTool.my_new_tool()
    ```

### Step 3: Update Tests

**Crucial:** Write tests for your new tool.

1.  **Unit Tests:** Create `test/cara/ai/tools/my_new_tool_test.exs`.
2.  **Integration Tests:** Verify the tool's integration in `test/cara_web/live/chat_live_test.exs` or `test/cara/ai/tool_handler_test.exs`.


By following these steps, you can effectively extend Cara's capabilities with new tools, allowing the AI companion to handle a wider range of user queries.