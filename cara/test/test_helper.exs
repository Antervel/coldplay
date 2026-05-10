Ecto.Adapters.SQL.Sandbox.mode(Cara.Repo, :manual)

Mox.defmock(Cara.HTTPClientMock, for: Cara.HTTPClientBehaviour)
Mox.defmock(Cara.AI.ChatMock, for: BranchedLLM.ChatBehaviour)

# Configure application to use mock in test
Application.put_env(:cara, :chat_module, Cara.AI.ChatMock)
Application.put_env(:cara, :disable_guard_globally, true)

ExUnit.start()
