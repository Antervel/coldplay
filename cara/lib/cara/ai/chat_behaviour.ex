defmodule Cara.AI.ChatBehaviour do
  @moduledoc """
  Behaviour for Chat AI interactions
  """
  alias ReqLLM.Context
  alias ReqLLM.Tool

  @callback new_context(String.t()) :: Context.t()
  @callback send_message_stream(String.t(), Context.t(), keyword()) ::
              {:ok, Enumerable.t(), (String.t() -> Context.t()), list()} | {:error, term()}
  @callback execute_tool(Tool.t(), map()) :: {:ok, term()} | {:error, term()}
end
