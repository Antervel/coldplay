defmodule Cara.AI.ChatBehaviour do
  @moduledoc """
  Behaviour for Chat AI interactions
  """

  @callback new_context(String.t()) :: term()
  @callback send_message_stream(String.t(), term()) ::
              {:ok, Enumerable.t(), (String.t() -> term())}
end
