# PRD — Cara: The AI Learning Companion

## 1. Overview

**Cara** is an AI-powered, interactive chat application designed as a friendly, safe, and engaging learning companion for school-aged students. It leverages Large Language Models (LLMs) to provide a personalized tutoring experience tailored to each student's age, subject area, and learning pace. 

Built with Elixir and the Phoenix Framework, Cara offers a real-time, streaming chat interface using Phoenix LiveView. Key features include:
- **Tone/Persona Adaptation**: Tailors explanations based on the student's age and subject.
- **Conversation Branching**: Supports non-linear learning paths via interactive message trees.
- **AI Tool Execution**: Embeds custom tools (like mathematical calculations and Wikipedia search) into the conversation loop.
- **Teacher Dashboard**: Provides real-time classroom monitoring with safety alerts and visibility into deleted messages.
- **Extensible Message Pipeline**: Leverages a plugin-based system to run cross-cutting safety checks, auditing, and dashboards updates.

## 2. Problem Statement

School-aged students benefit significantly from 1-on-1 tutoring, yet access to human tutors is limited. While generic Large Language Models (LLMs) can provide tutoring, they present several barriers for educational use:
1. **Inappropriate Explanations**: A 7-year-old and a 16-year-old require different terminology, examples, and depth when discussing topics like "gravity".
2. **Safety and Content Risks**: Standard chat interfaces do not filter out toxic, obscene, or age-inappropriate content from students or from the AI's generated responses.
3. **Linearity Constraints**: Standard chat models enforce linear dialogue, preventing students from diverging to explore tangent topics and then easily returning to the main lesson.
4. **Lack of Teacher Oversight**: Classroom teachers have no way to monitor what students are asking the AI, what the AI is responding with, or if students are attempting to delete search history or input inappropriate queries.

Cara resolves these issues with a real-time LiveView chat architecture that manages non-linear message trees, incorporates automated content safety guards, runs specialized math/wikipedia lookup tools, and exposes a real-time dashboard at `/teacher` for pedagogical oversight.

## 3. Goals

| # | Goal | Description |
|---|------|-------------|
| **G1** | **Personalized Explanations** | Dynamically adjust system prompts based on student parameters (name, age, subject) to target the appropriate cognitive/reading level. |
| **G2** | **Real-Time Streaming** | Provide low-latency, real-time message streaming using Phoenix LiveView. |
| **G3** | **Non-Linear Dialogue** | Enable students to branch off from any point in the history, allowing parallel exploration of concepts. |
| **G4** | **Content Safety Guard** | Intercept student messages and AI outputs to block unsafe content (toxicity, threat, obscenity, sexual content) using an external classification API. |
| **G5** | **Tool-Assisted Reasoning** | Empower the LLM to execute modular tools (e.g., calculator, Wikipedia retrieval) to solve logic/math problems and provide factual references. |
| **G6** | **Teacher Oversight Dashboard** | Provide a real-time multi-panel dashboard where teachers can view student chat trees, see deleted messages, and receive color-coded safety indicators. |
| **G7** | **Extensible Pipeline Architecture** | De-couple monitoring, safety check, and DB persistence from the core chat orchestration using a plugin-based message pipeline. |

## 4. Non-Goals

| # | Scope | Rationale |
|---|-------|-----------|
| **NG1** | **Production Authentication / RBAC** | Simple session cookies and stable UUIDs are sufficient for classroom identification; full identity providers (Auth0/Keycloak) are out of scope. |
| **NG2** | **Direct Classroom Interception** | The Teacher Dashboard is read-only; teachers cannot send direct text messages or override AI responses inside a student's session. |
| **NG3** | **On-Server Model Inference** | Running large generative models directly on the Phoenix server is avoided; inference runs via external endpoints (Ollama, OpenAI compatible endpoints). |
| **NG4** | **Dynamic Tool Generation** | The LLM cannot define new tools at runtime; all available tools must be registered beforehand inside the Elixir codebase. |

## 5. Architecture Overview

```
                        ┌──────────────────────────────────────────────┐
                        │              Client Browser                  │
                        └──────┬────────────────────────────────┬──────┘
                               │ Websocket / LiveView           │ Websocket / LiveView
                               ▼                                ▼
                    ┌─────────────────────┐          ┌─────────────────────┐
                    │  CaraWeb.ChatLive   │          │ CaraWeb.TeacherLive │
                    └──────────┬──────────┘          └──────────▲──────────┘
                               │                                │
                       Invokes │                                │ PubSub Events
                               ▼                                │ "teacher:monitor"
                    ┌─────────────────────┐                     │
                    │ Education.ChatService                     │
                    └──────────┬──────────┘                     │
                               │                                │
                   Runs Events │                                │
                               ▼                                │
  ┌──────────────────────────────────────────────────────────┐  │
  │ Education.MessagePipeline (Context)                      │  │
  │                                                          │  │
  │  ┌──────────────────┐  ┌──────────────────┐  ┌─────────┐ │  │
  │  │   SafetyPlugin   │  │ MonitoringPlugin │  │ Audit   │ │  │
  │  │ (Classifier API) │  │  (PubSub Broadcast)  │ (DB App)│ │  │
  │  └──────────────────┘  └──────────┬───────┘  └────┬────┘ │  │
  └───────────────────────────────────┼───────────────┼──────┘  │
                                      │ Broadcasts    │         │
                                      ▼               │         │
                             ┌─────────────────┐      │         │
                             │ Phoenix.PubSub  │──────┼─────────┘
                             └─────────────────┘      │ Async Task
                                                      ▼
                                             ┌─────────────────┐
                                             │ PostgreSQL (DB) │
                                             │  (audit_msgs)   │
                                             └─────────────────┘
```

The system is split into two primary layers:
1. **Frontend / Web Layer ([cara_web](file:///home/developer/coldplay/cara/lib/cara_web))**:
   - [chat_live.ex](file:///home/developer/coldplay/cara/lib/cara_web/live/chat_live.ex): Handles student UI, text validation, sidebar toggles, and async streaming updates.
   - [teacher_live.ex](file:///home/developer/coldplay/cara/lib/cara_web/live/teacher_live.ex): Displays a grid of active student sessions, rendering full message flows and highlighting deleted messages or safety flags.
   - [chat_components.ex](file:///home/developer/coldplay/cara/lib/cara_web/live/chat_components.ex): Provides reusable presentation wrappers for message bubbles, branching UI, and input panels.

2. **Core Domain & Backend Layer ([cara](file:///home/developer/coldplay/cara/lib/cara))**:
   - [chat_service.ex](file:///home/developer/coldplay/cara/lib/cara/education/chat_service.ex): Handles conversation orchestration (message sends, deletes, branch switches, cancellations).
   - [message_pipeline.ex](file:///home/developer/coldplay/cara/lib/cara/education/message_pipeline.ex): Runs `:on_message`, `:on_chunk`, and `:on_error` events sequentially across registered plugins.
   - [pipeline_plugin.ex](file:///home/developer/coldplay/cara/lib/cara/education/pipeline_plugin.ex): Defines the pipeline callbacks for plugins to hook into.
   - [chat.ex](file:///home/developer/coldplay/cara/lib/cara/ai/chat.ex): Wraps calls to `ReqLLM` (OpenAI or Ollama backend) to stream responses.
   - [guard.ex](file:///home/developer/coldplay/cara/lib/cara/ai/guard.ex): Interfaces with [content_classifier.ex](file:///home/developer/coldplay/cara/lib/cara/content_classifier.ex) to determine content safety.
   - [tools.ex](file:///home/developer/coldplay/cara/lib/cara/ai/tools.ex): Dispatches LLM tool calls (Calculator, Wikipedia search/retrieval).

## 6. API & Router Specification

All endpoints are configured inside the application router ([router.ex](file:///home/developer/coldplay/cara/lib/cara_web/router.ex)):

### HTTP Endpoints

- `GET /student`: Displays the onboarding form where the student inputs their `name`, `age`, and `subject` of interest.
- `POST /student`: Saves the onboarding details in the session cookie and redirects to `/chat`.
- `GET /chat`: Renders the main student chat screen. If the session configuration is missing, redirects to `/student`. If the AI server is offline, redirects to `/sleeping`.
- `GET /teacher`: Renders the Teacher Dashboard showing active student sessions.
- `GET /sleeping`: Displayed when the AI service fails its pre-mount health check.

---

### PubSub Event System (`"teacher:monitor"` Topic)

The Teacher Dashboard communicates with active student chat processes in real-time over Phoenix PubSub.

#### 1. `{:teacher_joined, nil}`
- **Sender**: `TeacherLive` on mount.
- **Receiver**: `ChatLive` processes.
- **Effect**: Signals active student screens to broadcast their full conversation state to the dashboard.

#### 2. `{:chat_started, %{id: chat_id, student: student_info}}`
- **Sender**: `ChatLive` on mount.
- **Description**: Registers a new active student panel on the teacher grid.
- **Data Shape**:
  ```elixir
  %{
    id: "uuid-1234",
    student: %{name: "Alice", age: 10, subject: "Science"}
  }
  ```

#### 3. `{:chat_left, %{id: chat_id}}`
- **Sender**: `ChatLive` on terminate.
- **Description**: Removes the student's panel from the teacher's dashboard.

#### 4. `{:chat_state, %{id: chat_id, student: student_info, messages: messages}}`
- **Sender**: `ChatLive` in response to a teacher joining.
- **Description**: Transmits the full dialogue history of the session to sync the dashboard.

#### 5. `{:new_message, %{chat_id: chat_id, message: message_obj}}`
- **Sender**: `MonitoringPlugin` inside the pipeline.
- **Description**: Broadcasts a new message (either student question or AI answer).
- **Data Shape**:
  ```elixir
  %{
    chat_id: "uuid-1234",
    message: %BranchedLLM.Message{
      id: "msg-99",
      role: :user,
      content: "Explain gravity",
      metadata: %{safety_score: 0.05}
    }
  }
  ```

#### 6. `{:message_deleted, %{chat_id: chat_id, message_id: message_id}}`
- **Sender**: `ChatService` on `delete_message/3`.
- **Description**: Tells the dashboard to mark a message as deleted (rendered with a strike-through).

---

## 7. Architecture & Design Decisions

### 7.1 State Machine and Message Queuing

To prevent out-of-order execution and text rendering collisions (which occur if a student submits a second prompt while the AI is still streaming the first response), Cara implements a visual and logical queuing system:

1. **Active Check**: On submission, [chat_service.ex](file:///home/developer/coldplay/cara/lib/cara/education/chat_service.ex) calls `BranchedChat.busy?(branched_chat, branch_id)`.
2. **Visual Queuing**: If busy, the message is placed in `pending_messages` and rendered at the bottom of the chat list with low opacity and a *"Queued..."* indicator.
3. **Sequential Execution**: When the current LLM streaming task emits its final chunk (`:llm_end`), `ChatLive` pops the next prompt from the queue, moves it to the active list, and triggers a new LLM task.

### 7.2 Cancellation Lifecycle

Students can immediately interrupt AI generations using the **Stop** button, which appears next to active streaming bubbles and thinking indicators:

1. **Process Termination**: Clicking "Stop" triggers a `cancel` event. The LiveView fetches the `active_task` PID for that branch and terminates it using `Process.exit(pid, :kill)`.
2. **State Clean Up**: The queue is flushed (`pending_messages = []`), and the orchestrator task is cleared.
3. **Context Recovery**: If the AI was already writing, the partial text is retained in the conversation context. If it hadn't started writing, a mock assistant bubble with the text `"*Cancelled*"` is appended to keep the linear structure valid.

### 7.3 Safety Classification

Message safety is assessed in [guard.ex](file:///home/developer/coldplay/cara/lib/cara/ai/guard.ex) which delegates to [content_classifier.ex](file:///home/developer/coldplay/cara/lib/cara/content_classifier.ex):

- **Target Scoping**: Configurable to check student input only, AI responses only, or both (`:all`).
- **Scope Context**: Safety check can run on the latest message only (`:latest_message`) or the concatenated history of the current branch (`:whole_conversation`).
- **External Integration**: Calls a `/score` endpoint on `classifier-api:8002` returning indicators for sexual content (NSFW/SFW) and detoxify categories (toxicity, severe toxicity, obscene, threat, insult, identity attack).
- **Threshold Matching**: If any score exceeds the configured threshold, the message is flagged `:unsafe`.

### 7.4 Message Pipeline Design

To maintain separation of concerns, the chat domain layer delegates side effects to a pipeline:

```elixir
# config/config.exs
config :cara, :message_pipeline, [
  Cara.Plugins.SafetyPlugin,      # Classifies content & sets status (:ok or :blocked)
  Cara.Plugins.MonitoringPlugin,  # Enriches message object & broadcasts to Teacher Dashboard
  Cara.Plugins.AuditPlugin        # Persists completed message to Postgres
]
```

1. **Context Struct**: `MessagePipeline.Context` maintains data fields, metadata maps, event types, and pipeline statuses.
2. **Sequence Execution**: `MessagePipeline.run/3` iterates over the list of plugins. Each plugin returns a modified context.
3. **Blocking**: If `SafetyPlugin` returns `:blocked`, the message content is discarded and replaced with the system-level blocked text.
4. **Asynchronous Persistence**: `AuditPlugin` triggers a database insertion using a fire-and-forget `Task.start/1` to ensure database writes do not slow down LiveView streaming.

---

### 7.5 Tool Reasoning Loop (Reason-Act-Answer)

Cara enables agentic capabilities using the `req_llm` tool specification:

1. **Instantiation**: [tools.ex](file:///home/developer/coldplay/cara/lib/cara/ai/tools.ex) compiles active `ReqLLM.Tool` structs (e.g., parsing arguments, exposing description schemas).
2. **Reason**: The LLM streams tool requests (`ReqLLM.ToolCall`) instead of content chunks.
3. **Act**: The LiveView intercepts the tool call, displays a status bubble (e.g. *"Using Wikipedia..."*), runs `execute_tool/2`, and appends the outcome as a `:tool` message to the history.
4. **Answer**: The LiveView calls the LLM recursively, sending the tool outcome. The LLM then responds with final text.
5. **Caching**: [tool_cache.ex](file:///home/developer/coldplay/cara/lib/cara/ai/tool_cache.ex) stores tool inputs/outputs in memory to bypass redundant web calls or heavy calculations on identical queries.

---

## 8. Deployment Strategy

### Containerization

The project uses a standard `Dockerfile` that packages the Phoenix application inside an alpine-based Elixir runtime:

- **Build Stage**: Installs Hex, Rebar, fetches dependencies, runs Tailwind and Esbuild, and builds a production release using `mix release`.
- **Runtime Stage**: A minimal, non-root user image containing only the compiled release.

### Local Development / Docker Compose

- A `docker-compose.yaml` setup spawns the following components:
  1. `db`: PostgreSQL container on port 15432.
  2. `ollama`: Hosting the local `cara-cpu` model.
  3. `classifier-api`: Hosting the safety classification model on port 8002.
  4. `cara`: The main web application serving on port 4000.

---

## 9. Configuration

Configuration options are managed inside [config.exs](file:///home/developer/coldplay/cara/config/config.exs), [dev.exs](file:///home/developer/coldplay/cara/config/dev.exs), and [runtime.exs](file:///home/developer/coldplay/cara/config/runtime.exs):

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `:ai_model` | `"openai:cara-cpu"` | String | Configures the AI endpoint backend name. |
| `:enable_teacher_monitoring` | `true` | Boolean | Toggles PubSub broadcasting to `/teacher`. |
| `:enabled_tools` | `[:calculator, :wikipedia_search]` | List | Enabled tools for LLM use. |
| `:content_classifier_settings` | `[enabled: true]` | Keyword List | Configures classifier target, scope, and blocked message. |
| `OLLAMA_URL` | `"http://localhost:11434/v1"` | Environment Var | Directs the HTTP requests to Ollama. |

---

## 10. Security Considerations

### 10.1 Safety Interception
By running both input (student) and output (AI) safety checks via the `SafetyPlugin`, students are protected from submitting inappropriate material, and the model is prevented from hallucinating unsafe or toxic output.

### 10.2 HTML/Markdown Sanitization
When rendering user inputs or AI responses (which support Markdown, Mermaid diagrams, and LaTeX math), the LiveView uses [markdown_helpers.ex](file:///home/developer/coldplay/cara/lib/cara_web/markdown_helpers.ex) and `sanitize: true` parameters to ensure that arbitrary `<script>` tags or malicious HTML injection vectors are stripped out before parsing.

### 10.3 DB Boundary Isolation
Audit logs are written in a structured table without raw query construction, protecting the system from SQL Injection.

---

## 11. Success Criteria

| # | Criterion | Target | Verification Method |
|---|-----------|--------|---------------------|
| **SC1** | **Real-Time Responsiveness** | Server handles streaming updates without blocking the browser thread. | Test via LiveView streaming tests |
| **SC2** | **Queuing Integrity** | Out-of-order messages are held in a visual queue and processed sequentially. | verified by `chat_live_test.exs` |
| **SC3** | **Immediate Interruption** | generation stops instantly upon clicking the Stop button. | Verify active task process is killed |
| **SC4** | **Safety Enforcement** | Flagged content is successfully replaced with the block text. | `guard_test.exs` integration tests |
| **SC5** | **Dashboard Alerts** | Teacher dashboard highlights high-risk sessions with red/yellow borders. | PubSub broadcast payload evaluation |
| **SC6** | **Deleted Message Persistence** | Deleted messages remain visible with a strike-through on the teacher screen. | Manual dashboard review / unit tests |

---

## 12. Risks & Mitigation

### R1: AI Model Latency or Offline Outage
- **Impact**: High. Students will see a hanging screen or empty bubbles.
- **Mitigation**: `mount` processes run a synchronous health check against the model endpoint. If offline, the student is redirected to `/sleeping` showing a friendly fallback state.

### R2: Ecto Database Sandbox Errors in Async Tasks
- **Impact**: Medium (developer-only). Async database writes in `AuditPlugin` fail in ExUnit tests due to ownership checkout limits.
- **Mitigation**: Plugins utilize configurable insertion functions. In tests, the insertion function is overridden to run synchronously, ensuring the sandbox transaction covers the write.

### R3: Classifier Service Downtime
- **Impact**: High. If the classifier is offline, the chat could block all messages or fail silently.
- **Mitigation**: If the HTTP call to `classifier-api:8002` fails or times out, the `ContentClassifier` defaults to returning `{:unsafe, 1.0}`, keeping the system secure by default until connection is restored.

---

## 13. Open Questions & Future Work

1. **Student Progress Tracking**: Adding automated summaries of student questions to help teachers identify academic weaknesses.
2. **Interactive Intervention**: Allowing teachers to pause or terminate student chats directly from the dashboard.
3. **Offline Retrieval Augmented Generation (RAG)**: Integrating a local vector store (e.g. index/semantic search similar to Wikipedia title lookup) to feed high-quality classroom articles directly to the AI without outbound internet access.
