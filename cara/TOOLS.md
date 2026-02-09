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
    *   Its `call_llm/3` private function determines whether to use `ReqLLM.generate_text` (to check for tool calls) or `ReqLLM.stream_text` (for streaming text responses).
    *   It also provides the `execute_tool/2` function, which wraps `ReqLLM.Tool.execute/2` to run a tool's callback.

*   **`Cara.AI.ChatBehaviour` (`lib/cara/ai/chat_behaviour.ex`):**
    *   Defines the contract for any chat module in Cara.
    *   It includes `@callback` definitions for functions like `send_message_stream/3` (which now supports passing tools) and `execute_tool/2`, ensuring consistency across different LLM implementations or mocks.

*   **`Cara.AI.ToolHandler` (`lib/cara/ai/tool_handler.ex`):**
    *   This module contains pure functions responsible for processing tool calls and managing context updates.
    *   It iterates through requested tool calls, finds the corresponding tool, executes it using `Cara.AI.Chat.execute_tool/2`, and appends the results (or errors) to the conversation context.
    *   It was extracted from `CaraWeb.ChatLive` for better testability and separation of concerns.

*   **`CaraWeb.ChatLive` (`lib/cara_web/live/chat_live.ex`):**
    *   This Phoenix LiveView module orchestrates the entire chat interaction, including the tool execution loop.
    *   It holds the list of available tools in its `llm_tools` assign.
    *   Its `process_llm_request` function manages the "Reason-Act-Answer" loop:
        1.  **Reason:** Calls `Cara.AI.Chat.send_message_stream` to send the user's message and available tools to the LLM. The LLM either generates a text response or requests a tool call.
        2.  **Act:** If tool calls are requested by the LLM, `handle_llm_stream_response` first adds an `assistant` message with the tool calls to the context. Then, it delegates to `Cara.AI.ToolHandler.handle_tool_calls` to execute each requested tool, and its results are appended to the conversation context as `tool` messages.
        3.  **Answer:** With the tool results now in the conversation context, `process_llm_request` makes another call to the LLM (recursive call to `process_llm_request`) for a final, natural language answer based on the tool's output. If no tools were called, it directly processes the streamed text response.

*   **Specific Tool Modules (e.g., `Cara.AI.Tools.Calculator`):**
    *   These modules define the actual tools. Each module typically exposes a function (e.g., `calculator_tool/0`) that returns a `ReqLLM.Tool` struct configured with its specific logic.

## 3. Tool Execution Flow (Reason-Act-Answer Loop)

When a user interacts with the AI and their query requires a tool, the following sequence of events occurs:

1.  **User Input:** The user types a message (e.g., "What is 123 * 45?").
2.  **Initial LLM Call (`CaraWeb.ChatLive.process_llm_request` -> `Cara.AI.Chat.call_llm`):**
    *   The system sends the current conversation context (including system prompt and user message) along with the list of available tools to the LLM using `ReqLLM.generate_text`.
    *   The LLM processes this and decides if a tool is needed.
3.  **Tool Call Detected:**
    *   If the LLM decides to use a tool, it returns a `ReqLLM.Response` containing one or more `ReqLLM.ToolCall` structs.
    *   `Cara.AI.Chat.call_llm` detects these tool calls and returns them to `CaraWeb.ChatLive.handle_llm_stream_response`.
4.  **Orchestration in `CaraWeb.ChatLive.handle_llm_stream_response`:**
    *   An `assistant` message containing the `tool_calls` is appended to the conversation context. This message acts as a "tool instruction" for the LLM.
    *   The execution then moves to `Cara.AI.ToolHandler.handle_tool_calls` which processes the tool calls.
5.  **Tool Execution (`Cara.AI.ToolHandler.handle_tool_calls`):**
    *   `Cara.AI.ToolHandler.handle_tool_calls` iterates through each `ReqLLM.ToolCall`.
    *   For each tool call, it finds the corresponding `ReqLLM.Tool` from the `llm_tools` list.
    *   `Cara.AI.Chat.execute_tool/2` is invoked (via the `chat_module` parameter passed to `ToolHandler`), which executes the `callback` function defined within the `ReqLLM.Tool`, passing the LLM-provided arguments.
    *   The result of the tool's execution (or an error message) is then appended to the conversation context as a `tool` message (`ReqLLM.Context.tool_result`).
6.  **Second LLM Call (Recursion):**
    *   After all tools have been executed and their results added to the context, `process_llm_request` is called recursively with the updated conversation context.
    *   This time, the LLM receives the full history, including its own tool call requests and the tool's outputs.
7.  **Final Answer:**
    *   The LLM generates a natural language response based on the tool results. This response is then streamed back to the user interface.

## 4. HOWTO: Adding a New Tool

Follow these steps to add a new tool to the Cara application:

### Step 1: Define the Tool Module

Create a new `.ex` file for your tool definition, typically in `lib/cara/ai/tools/`.

**Example: `lib/cara/ai/tools/my_new_tool.ex`**

```elixir
defmodule Cara.AI.Tools.MyNewTool do
  @moduledoc """
  A description of what MyNewTool does.
  """
  alias ReqLLM.Tool

  def my_new_tool() do
    Tool.new!(
      name: "my_new_tool", # Must be a unique, snake_case string
      description: ~s|A clear, concise description of what the tool does and when to use it. Include example JSON for parameters. Example: {"param1": "value"}|,
      parameter_schema: [ # Define the schema for the tool's input arguments
        param1: [type: :string, required: true, doc: "Description of param1"],
        param2: [type: :integer, required: false, doc: "Description of param2"]
      ],
      callback: fn args ->
        # Implement the tool's logic here.
        # `args` will be a map containing the parameters passed by the LLM.
        # It's good practice to handle both atom and string keys (e.g., args[:param1] || args["param1"])
        value1 = args[:param1] || args["param1"]
        value2 = args[:param2] || args["param2"]

        # Perform the action (e.g., API call, data processing, complex calculation)
        result = "Processed #{value1} and #{value2}" # Replace with actual logic

        # Return {:ok, result} on success, or {:error, reason} on failure
        {:ok, result}
      end
    )
  end
end
```
**Important Considerations:**
*   Ensure the `callback` function is robust and handles various inputs and potential errors.

### Step 2: Integrate with `CaraWeb.ChatLive`

Modify `lib/cara_web/live/chat_live.ex` to make your new tool available to the LLM.

1.  **Import the Tool Module:**
    Add an `alias` for your new tool module at the top of the file:
    ```elixir
    alias Cara.AI.Tools.MyNewTool
    ```

2.  **Instantiate and Add to `llm_tools`:**
    In the `mount/3` function, instantiate your tool and add it to the `llm_tools` list in the socket assigns.
    ```elixir
      def mount(_params, session, socket) do
        # ... existing code ...
        calculator_tool = Calculator.calculator_tool()
        my_new_tool = MyNewTool.my_new_tool() # Instantiate your new tool

        {:ok,
         assign(socket,
           # ... existing assigns ...
           llm_tools: [calculator_tool, my_new_tool] # Add your tool here
         )}
      end
    ```

### Step 3: Update Chat Behaviour (if necessary)

If your new tool introduces a completely new interaction pattern that cannot be handled by the existing `Cara.AI.Chat` functions, you might need to extend `Cara.AI.ChatBehaviour` (`lib/cara/ai/chat_behaviour.ex`) with new callbacks. For most standard tools, this step is not necessary as `send_message_stream/3` and `execute_tool/2` are generic enough.

### Step 4: Update Tests

**Crucial:** Write tests for your new tool.

1.  **Unit Tests for the Tool Module:**
    Create a test file (e.g., `test/cara/ai/tools/my_new_tool_test.exs`) to verify your tool's `callback` logic works correctly in isolation.

2.  **Integration Tests in `CaraWeb.ChatLiveTest` (and potentially `Cara.AI.ToolHandlerTest`):**
    If the tool interacts with external services, consider mocking those services. Create tests in `test/cara_web/chat_live_test.exs` that simulate a user asking a question that should trigger your tool, and assert that the tool is called and its results are processed correctly. For more focused testing of tool execution logic, consider adding tests to `test/cara/ai/tool_handler_test.exs` that directly verify how `Cara.AI.ToolHandler` processes tool calls and updates the context. Remember to mock `Cara.AI.ChatMock` appropriately for your tests.

By following these steps, you can effectively extend Cara's capabilities with new tools, allowing the AI companion to handle a wider range of user queries.