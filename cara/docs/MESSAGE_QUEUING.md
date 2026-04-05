# Message Queuing and Cancellation

This document describes the implementation of message queuing and cancellation in the Cara chat interface.

## Overview

To prevent "scrambled" responses and provide a smoother user experience, Cara implements a sequential message queue. If a user sends multiple messages while the AI is still generating a response, those messages are queued and processed one by one. Additionally, users can cancel the current generation at any time.

## Message Queuing

### How it works
1.  **Submission:** When a user submits a message, it is immediately added to the `pending_messages` list.
2.  **Visual Queuing:** The UI displays these messages with a "Queued..." label and reduced opacity at the bottom of the chat, providing immediate feedback without breaking the current AI flow.
3.  **Busy Check:** The system checks if an `active_task` (the AI generation process) is currently running.
4.  **Processing:**
    -   If the AI is **idle**, the message is moved to `chat_messages` and processed immediately.
    -   If the AI is **busy**, the message stays in the visual queue.
5.  **Sequential Processing:** When the current AI task finishes, the system pops the next message from the queue, moves it to the main `chat_messages` list, and starts the new AI task. This ensures a user message always separates two AI responses, keeping them in independent bubbles.

### Technical Implementation
The state is managed in `CaraWeb.ChatLive` via the `@branched_chat` assign, which uses the `Cara.AI.BranchedChat` struct. Each conversation branch independently manages its own queuing state:
- `active_task`: The PID of the asynchronous task handling the LLM request for that branch.
- `pending_messages`: A list of strings representing messages waiting for processing in that branch.
- `current_user_message`: The message currently being answered by the AI in that branch.

This branched approach ensures that the AI can work on multiple paths simultaneously if the user switches between them, while maintaining strict sequential integrity within any single branch.

## Cancellation

Users can interrupt the AI at any time by clicking the **Stop** button.

### How it works
1.  **Interruption:** Clicking "Stop" sends a `cancel` event to the LiveView.
2.  **Process Termination:** The `active_task` process is immediately killed using `Process.exit(pid, :kill)`.
3.  **Queue Clearing:** The `pending_messages` list is cleared, preventing any queued messages from starting.
4.  **Context Patching:**
    -   The system ensures the conversation history (LLM context) remains consistent.
    -   If the AI had already started responding, the partial response is kept.
    -   If the AI was still "thinking" or no response was generated, a "*Cancelled*" message is appended to the chat.

## UI Elements

### Stop Button
-   The Stop button (a red stop icon) appears in two places:
    -   Next to the "Thinking..." or "Using [Tool]..." status bubble.
    -   Next to the assistant's message bubble while text is actively streaming.
-   The button is unobtrusive and provides immediate visual feedback when the system is busy.

### Visual Feedback
-   When a message is queued, it appears in the chat immediately, but the AI does not start "Thinking..." for it until the previous response is done.
-   When cancelled, the active response bubble stops updating and displays its final state (either the partial text or a "*Cancelled*" placeholder).
