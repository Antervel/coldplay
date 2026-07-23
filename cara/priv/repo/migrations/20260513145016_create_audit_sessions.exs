defmodule Cara.Repo.Migrations.CreateAuditSessions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:audit_sessions) do
      add :chat_id, :string, null: false
      add :student_name, :string
      add :student_age, :integer
      add :student_subject, :string
      timestamps()
    end

    create unique_index(:audit_sessions, [:chat_id], concurrently: true)
    create index(:audit_sessions, [:inserted_at], concurrently: true)
  end
end
