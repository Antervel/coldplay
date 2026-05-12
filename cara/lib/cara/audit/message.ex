defmodule Cara.Audit.Message do
  @moduledoc """
  Schema for auditing chat messages to Postgres.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_messages" do
    field :chat_id, :string
    field :message_id, :string
    field :role, :string
    field :content, :string
    field :metadata, :map
    field :branch_id, :string
    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          chat_id: String.t() | nil,
          message_id: String.t() | nil,
          role: String.t() | nil,
          content: String.t() | nil,
          metadata: map() | nil,
          branch_id: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:chat_id, :message_id, :role, :content, :metadata, :branch_id])
    |> validate_required([:chat_id, :message_id, :role, :content])
  end
end
