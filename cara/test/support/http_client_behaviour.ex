defmodule Cara.HTTPClientBehaviour do
  @callback get(url :: String.t(), options :: Keyword.t() | map()) ::
              {:ok, Req.Response.t()} | {:error, term()}
end
