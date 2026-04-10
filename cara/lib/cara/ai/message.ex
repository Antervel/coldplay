defmodule Cara.AI.Message do
  @moduledoc """
  Generic AI message structure used across the system.
  """

  defstruct [
    :id,
    :sender,
    :content,
    deleted: false,
    metadata: %{}
  ]

  @type sender :: :user | :assistant | :system
  @type t :: %__MODULE__{
          id: String.t(),
          sender: sender(),
          content: String.t(),
          deleted: boolean(),
          metadata: map()
        }

  @doc """
  Creates a new message.
  """
  def new(sender, content, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, Ecto.UUID.generate()),
      sender: sender,
      content: content,
      deleted: Keyword.get(opts, :deleted, false),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
