defmodule Cara.Repo.Migrations.CreateAuditMessages do
  use Ecto.Migration

  def change do
    create table(:audit_messages) do
      add :chat_id, :string, null: false
      add :message_id, :string, null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map
      add :branch_id, :string
      timestamps(updated_at: false)
    end

    create index(:audit_messages, [:chat_id])
    create index(:audit_messages, [:chat_id, :branch_id])
  end
end
