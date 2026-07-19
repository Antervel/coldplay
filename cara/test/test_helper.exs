Ecto.Adapters.SQL.Sandbox.mode(Cara.Repo, :manual)

Mox.defmock(Cara.HTTPClientMock, for: Cara.HTTPClientBehaviour)
Mox.defmock(Cara.AI.ChatMock, for: BranchedLLM.ChatBehaviour)
Mox.defmock(Cara.AI.ChatClientMock, for: BranchedLLM.ChatClientBehaviour)

# Configure application to use mock in test
Application.put_env(:cara, :chat_module, Cara.AI.ChatMock)
Application.put_env(:cara, :orchestrator_chat_module, Cara.AI.ChatClientMock)
Application.put_env(:cara, :disable_guard_globally, true)

# Disable audit fire-and-forget inserts by default in tests
# (AuditPluginTest overrides this with a synchronous insert fn)
Application.put_env(:cara, :audit_insert_fn, fn _attrs -> :ok end)

ExUnit.start()
