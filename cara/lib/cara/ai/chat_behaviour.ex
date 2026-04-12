defmodule Cara.AI.ChatBehaviour do
  @moduledoc """
  Behaviour for Chat AI interactions.

  This re-exports `BranchedLLM.ChatBehaviour` for backward compatibility.
  """

  alias BranchedLLM.Chat

  # Re-declare the callbacks so that @impl Cara.AI.ChatBehaviour resolves correctly
  @callback new_context(String.t()) :: ReqLLM.Context.t()
  @callback reset_context(ReqLLM.Context.t()) :: ReqLLM.Context.t()
  @callback send_message_stream(String.t(), ReqLLM.Context.t(), keyword()) ::
              {:ok, ReqLLM.StreamResponse.t(), (String.t() -> ReqLLM.Context.t()), list()}
              | {:error, term()}
  @callback send_message(String.t(), ReqLLM.Context.t(), keyword()) ::
              {:ok, String.t(), ReqLLM.Context.t()} | {:error, term()}
  @callback execute_tool(ReqLLM.Tool.t(), map()) :: {:ok, term()} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}

  # For code that calls Cara.AI.ChatBehaviour functions as a passthrough,
  # delegate to the default implementation.
  defdelegate new_context(system_prompt), to: Chat
  defdelegate reset_context(context), to: Chat
  defdelegate send_message_stream(message, context, opts), to: Chat
  defdelegate send_message(message, context, opts), to: Chat
  defdelegate execute_tool(tool, args), to: Chat
  defdelegate health_check(), to: Chat
end
