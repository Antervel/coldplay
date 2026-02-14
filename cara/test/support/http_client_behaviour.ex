defmodule Cara.HTTPClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client, used for mocking HTTP requests in tests.
  """
  @callback get(url :: String.t(), options :: Keyword.t() | map()) ::
              {:ok, Req.Response.t()} | {:error, term()}
end
