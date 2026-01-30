defmodule Cara.ReqLLMBehaviour do
  @moduledoc """
  Behaviour for mocking ReqLLM.
  """
  @type stream_response :: %{stream: Enumerable.t()}

  @callback generate_text(model :: String.t(), prompt :: String.t()) :: {:ok, any()} | {:error, any()}
  @callback stream_text(model :: String.t(), messages :: list()) :: {:ok, stream_response} | {:error, term()}
end
