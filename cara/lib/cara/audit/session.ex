defmodule Cara.Audit.Session do
  @moduledoc """
  Schema for auditing student chat sessions to Postgres.

  One row per student session, created when the student logs in
  via `StudentController.create`. Links the ephemeral `chat_id`
  to student identity for archival and legal purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_sessions" do
    field :chat_id, :string
    field :student_name, :string
    field :student_age, :integer
    field :student_subject, :string
    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          chat_id: String.t() | nil,
          student_name: String.t() | nil,
          student_age: integer() | nil,
          student_subject: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:chat_id, :student_name, :student_age, :student_subject])
    |> validate_required([:chat_id])
    |> unique_constraint(:chat_id)
  end
end
