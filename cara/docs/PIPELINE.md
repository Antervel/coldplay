# Message Pipeline System

The message pipeline is an extensible plugin system that processes every chat message in Cara. It provides a unified point for safety classification, monitoring, auditing, and any other cross-cutting concern — without modifying `ChatService` directly.

## Architecture

```
User sends message ──► ChatService.send_message/3
                        │
                        ▼
              MessagePipeline.run(:on_message, data)
                        │
                        ▼
              ┌─────────────────────┐
              │  SafetyPlugin       │  ← classifies content, may block
              │  MonitoringPlugin   │  ← enriches message, broadcasts to teacher
              │  AuditPlugin        │  ← persists to Postgres
              │  ...your plugin...  │
              └─────────────────────┘
                        │
                        ▼
              ChatService checks context.status
                        │
                ┌───────┴───────┐
                │               │
           :blocked            :ok
                │               │
          Returns blocked   Continues to LLM
```

The same flow runs when the LLM finishes its response (`ChatService.finish_ai_response/4`), and an `:on_error` event fires when error messages are added.

## How It Works

### Pipeline Engine (`Cara.Education.MessagePipeline`)

The engine is a simple reduce over a list of plugins:

1. Builds a `Context` struct from the incoming data
2. Calls each plugin's callback in order, threading the context through
3. Returns the final context to the caller

Plugin order matters — earlier plugins can set metadata that later plugins read. For example, `SafetyPlugin` writes `safety_score` into `context.metadata`, and `MonitoringPlugin` reads it to enrich the message before broadcasting.

### Context Struct

Every plugin callback receives a `Cara.Education.MessagePipeline.Context`:

| Field | Type | Description |
|-------|------|-------------|
| `content` | `String.t() \| nil` | The message text |
| `role` | `atom() \| nil` | `:student` or `:llm` |
| `event` | `atom() \| nil` | `:on_message`, `:on_chunk`, or `:on_error` |
| `branched_chat` | `BranchedChat.t() \| nil` | The full conversation state |
| `socket` | `Phoenix.Socket \| nil` | The LiveView socket |
| `chat_id` | `String.t() \| nil` | The student session UUID |
| `metadata` | `map()` | Shared metadata between plugins (default `%{}`) |
| `status` | `atom()` | Pipeline status — `:ok` or `:blocked` (default `:ok`) |
| `assigns` | `map()` | Plugin-specific data (default `%{}`) |

**Key fields for inter-plugin communication:**

- **`metadata`** — shared map that plugins read and write. Early plugins add data (e.g. `safety_score`), later plugins consume it.
- **`status`** — set to `:blocked` by any plugin to stop the message. `ChatService` checks this after the pipeline runs.
- **`assigns`** — carries the `message_obj` (the `BranchedLLM.Message` struct) so plugins can enrich it.

### Events

| Event | When it fires | Who triggers it |
|-------|---------------|-----------------|
| `:on_message` | Student sends a message, or LLM finishes a response | `ChatService.send_message/3`, `ChatService.finish_ai_response/4` |
| `:on_chunk` | Each streaming chunk arrives from the LLM | `ChatService.handle_chunk/4` |
| `:on_error` | An error message is added | `ChatService.add_error_message/4` |

> **Note:** All three events now fire at the **ChatService layer**. The LiveView receives `:llm_chunk` messages from the ChatOrchestrator and delegates to `ChatService.handle_chunk/4`, which runs the pipeline and appends the chunk to the branched chat. The LiveView only handles presentation (rendering Markdown → HTML, pushing to the client). Currently no plugin does meaningful work on `:on_chunk` — `MonitoringPlugin` has the callback but calls `super` (no-op). The hook is wired and ready for future use (e.g. token counting, throttled teacher broadcasts).

The `role` field distinguishes the source: `:student` for user messages, `:llm` for AI responses.

### Blocking

Any plugin can block a message by setting `context.status` to `:blocked`. When the pipeline finishes, `ChatService` checks this:

- **Student message blocked** → the message is kept but a blocked assistant response is added
- **LLM response blocked** → the AI's content is replaced with the blocked message text

Only one plugin needs to block — the status is checked after *all* plugins have run.

## Existing Plugins

### SafetyPlugin (`Cara.Plugins.SafetyPlugin`)

Classifies every message through `Cara.AI.Guard` for content safety. Sets `context.status` to `:blocked` when classification returns `:unsafe`, and writes `safety_score` into `context.metadata` for downstream plugins.

### MonitoringPlugin (`Cara.Plugins.MonitoringPlugin`)

Enriches the message object with pipeline metadata (e.g. `safety_score`) and broadcasts it to the teacher dashboard via `Monitoring.broadcast_new_message/3`. Updates `context.assigns.message_obj` so subsequent plugins see the enriched version.

### AuditPlugin (`Cara.Plugins.AuditPlugin`)

Persists every completed message to the `audit_messages` Postgres table. Uses fire-and-forget `Task.start/1` so a slow DB write never blocks the pipeline. Only hooks `:on_message` (not `:on_chunk`) to avoid overwhelming the database.

---

# How to Add a New Plugin

## 1. Create the module

Every plugin `use`s `Cara.Education.PipelinePlugin`, which provides default no-op implementations for all three callbacks. Override only the ones you need:

```elixir
# lib/cara/plugins/my_plugin.ex
defmodule Cara.Plugins.MyPlugin do
  use Cara.Education.PipelinePlugin

  @impl true
  def on_message(context, _opts) do
    # Your logic here
    context
  end
end
```

## 2. Register it in config

Add your plugin to the `:message_pipeline` list in `config/config.exs`. Order matters — plugins run sequentially:

```elixir
config :cara, :message_pipeline, [
  Cara.Plugins.SafetyPlugin,      # 1st: classify & set status
  Cara.Plugins.MonitoringPlugin,  # 2nd: enrich & broadcast
  Cara.Plugins.MyPlugin,          # 3rd: your plugin
  Cara.Plugins.AuditPlugin        # last: persist to DB
]
```

## 3. Test it

Create a test file in `test/cara/plugins/`. Build a `Context` struct directly and call your plugin:

```elixir
# test/cara/plugins/my_plugin_test.exs
defmodule Cara.Plugins.MyPluginTest do
  use ExUnit.Case, async: true

  alias Cara.Education.MessagePipeline.Context
  alias Cara.Plugins.MyPlugin

  test "on_message does something useful" do
    context = %Context{
      content: "Hello",
      role: :student,
      event: :on_message,
      chat_id: "chat-123",
      metadata: %{},
      assigns: %{}
    }

    result = MyPlugin.on_message(context, [])
    assert result.status == :ok
  end
end
```

If your plugin hits the database, use `Cara.DataCase` and set the `:audit_insert_fn` pattern (or similar) to make inserts synchronous in tests:

```elixir
defmodule Cara.Plugins.MyPluginTest do
  use Cara.DataCase, async: true

  setup do
    # Override any fire-and-forget behavior for test assertions
    Application.put_env(:cara, :my_plugin_insert_fn, &sync_insert/1)
    on_exit(fn -> Application.delete_env(:cara, :my_plugin_insert_fn) end)
    :ok
  end

  defp sync_insert(attrs) do
    %MySchema{}
    |> MySchema.changeset(attrs)
    |> Repo.insert()
  end
end
```

## Common Patterns

### Reading metadata from earlier plugins

```elixir
def on_message(context, _opts) do
  safety_score = context.metadata[:safety_score] || 0.0
  # Use it...
  context
end
```

### Writing metadata for later plugins

```elixir
def on_message(context, _opts) do
  %{context | metadata: Map.put(context.metadata, :my_field, value)}
end
```

### Blocking a message

```elixir
def on_message(context, _opts) do
  if should_block?(context) do
    %{context | status: :blocked}
  else
    context
  end
end
```

### Enriching the message object

```elixir
def on_message(context, _opts) do
  case context.assigns[:message_obj] do
    nil -> context
    msg ->
      enriched = %{msg | metadata: Map.put(msg.metadata, :my_flag, true)}
      %{context | assigns: Map.put(context.assigns, :message_obj, enriched)}
  end
end
```

### Fire-and-forget side effects

For expensive operations (DB writes, HTTP calls) that shouldn't block the pipeline:

```elixir
def on_message(context, _opts) do
  if context.chat_id do
    Task.start(fn -> do_expensive_work(context) end)
  end
  context
end
```

**Important:** If you use `Task.start/1` with `Cara.Repo`, set a no-op default in `test/test_helper.exs` and override it in your plugin's test to avoid `DBConnection.OwnershipError` in other test suites:

```elixir
# test/test_helper.exs
Application.put_env(:cara, :my_plugin_side_effect_fn, fn _attrs -> :ok end)
```

### Passing options to a plugin

Plugins can be registered as `{module, opts}` tuples:

```elixir
config :cara, :message_pipeline, [
  Cara.Plugins.SafetyPlugin,
  {Cara.Plugins.MyPlugin, threshold: 0.8}
]
```

The `opts` keyword list is passed as the second argument to the callback:

```elixir
def on_message(context, opts) do
  threshold = Keyword.get(opts, :threshold, 0.5)
  # ...
end
```

## Checklist

- [ ] Module `use`s `Cara.Education.PipelinePlugin`
- [ ] Only overrides callbacks you need (`on_message/2`, `on_chunk/2`, `on_error/2`)
- [ ] Always returns the (possibly modified) `context`
- [ ] Registered in `config/config.exs` `:message_pipeline` list in the right order
- [ ] Fire-and-forget side effects use `Task.start/1` and don't block the pipeline
- [ ] Test helper has a no-op for any async side-effect function to prevent sandbox errors
- [ ] Plugin test uses `Cara.DataCase` if DB access is needed
- [ ] `mix precommit` passes (format, credo, dialyzer, tests)
