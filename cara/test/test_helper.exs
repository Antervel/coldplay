Ecto.Adapters.SQL.Sandbox.mode(Cara.Repo, :manual)

# Define the mock

Mox.defmock(Cara.HTTPClientMock, for: Cara.HTTPClientBehaviour)
Mox.defmock(Cara.AI.ChatMock, for: Cara.AI.ChatBehaviour)

# Configure application to use mock in test
Application.put_env(:cara, :chat_module, Cara.AI.ChatMock)

ExUnit.start()
