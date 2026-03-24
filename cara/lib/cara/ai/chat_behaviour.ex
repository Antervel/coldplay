defmodule Cara.AI.ChatBehaviour do
  @moduledoc """
  Behaviour for Chat AI interactions
  """
  alias ReqLLM.Context
  alias ReqLLM.Tool

  @callback new_context(String.t()) :: Context.t()
  @callback reset_context(Context.t()) :: Context.t()
  @callback send_message_stream(String.t(), Context.t(), keyword()) ::
              {:ok, ReqLLM.StreamResponse.t(), (String.t() -> Context.t()), list()} | {:error, term()}
  @callback send_message(String.t(), Context.t(), keyword()) ::
              {:ok, String.t(), Context.t()} | {:error, term()}
  @callback execute_tool(Tool.t(), map()) :: {:ok, term()} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}
end
