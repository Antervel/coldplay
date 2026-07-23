defmodule Cara.Repo.Migrations.CreateToolResults do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:tool_results) do
      add :tool_name, :string, null: false
      add :args, :jsonb, null: false
      add :result, :text, null: false

      timestamps()
    end

    create index(:tool_results, [:tool_name, :args], concurrently: true)
  end
end
