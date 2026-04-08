Ecto.Adapters.SQL.Sandbox.mode(Cara.Repo, :manual)

# Define the mock

Mox.defmock(Cara.HTTPClientMock, for: Cara.HTTPClientBehaviour)
Mox.defmock(Cara.AI.ChatMock, for: Cara.AI.ChatBehaviour)

# Default stubs for HTTPClientMock to avoid crashes when greeting prompt is rendered
Mox.stub(Cara.HTTPClientMock, :get, fn _url, _opts -> {:ok, %{status: 200, body: []}} end)
Mox.stub(Cara.HTTPClientMock, :put, fn _url, _opts -> {:ok, %{status: 200}} end)

# Configure application to use mock in test
Application.put_env(:cara, :chat_module, Cara.AI.ChatMock)

ExUnit.start()
