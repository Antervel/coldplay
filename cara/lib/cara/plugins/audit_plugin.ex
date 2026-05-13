defmodule Cara.Plugins.AuditPlugin do
  @moduledoc """
  A pipeline plugin that persists completed messages to Postgres for auditing.

  Only listens to `:on_message` events (not `:on_chunk`) to avoid
  overwhelming the database with chunk-level inserts.

  In non-test environments, inserts are fire-and-forget via `Task.start/1`
  so a slow DB write never blocks the pipeline. In test mode, inserts
  are synchronous so assertions can verify them.
  """

  use Cara.Education.PipelinePlugin

  alias Cara.Audit.Message
  alias Cara.Repo

  @impl true
  def on_message(context, _opts) do
    message_obj = context.assigns[:message_obj]

    if message_obj && context.chat_id do
      attrs = %{
        chat_id: context.chat_id,
        message_id: message_obj.id,
        role: to_string(message_obj.role),
        content: message_obj.content,
        metadata: context.metadata,
        branch_id: context.branched_chat.current_branch_id
      }

      insert_fn = Application.get_env(:cara, :audit_insert_fn, &default_insert/1)
      insert_fn.(attrs)
    end

    context
  end

  defp default_insert(attrs) do
    Task.start(fn ->
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()
    end)
  end
end
