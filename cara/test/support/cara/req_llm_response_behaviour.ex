defmodule Cara.ReqLLMResponseBehaviour do
  @moduledoc """
  Behaviour for mocking ReqLLM.Response.
  """
  @callback text(response :: any()) :: String.t()
end
