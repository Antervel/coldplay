defmodule Cara.Repo.Migrations.CreateToolResults do
  use Ecto.Migration

  def change do
    create table(:tool_results) do
      add :tool_name, :string, null: false
      add :args, :jsonb, null: false
      add :result, :text, null: false

      timestamps()
    end

    create index(:tool_results, [:tool_name, :args])
  end
end
