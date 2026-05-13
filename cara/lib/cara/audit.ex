defmodule Cara.Audit do
  @moduledoc """
  Context module for querying audit data — chat sessions and messages.

  Used by the `/logs` viewer for archival and legal purposes.
  """

  import Ecto.Query
  alias Cara.Audit.Message
  alias Cara.Audit.Session
  alias Cara.Repo

  @per_page 50

  @doc """
  Lists conversation branches with their message counts, student identity,
  and a preview of the first user message.

  Each `(chat_id, branch_id)` pair is a separate entry — a branch is
  a distinct conversation thread. This means one student session can
  produce multiple log entries if they branch off.

  Returns a tuple of `{branches, total_count}` for pagination.
  """
  def list_branches(opts \\ []) do
    search = Keyword.get(opts, :search)
    page = Keyword.get(opts, :page, 1)

    base_query =
      from m in Message,
        left_join: s in Session,
        on: m.chat_id == s.chat_id,
        group_by: [m.chat_id, m.branch_id, s.id],
        select: %{
          chat_id: m.chat_id,
          branch_id: m.branch_id,
          student_name: s.student_name,
          student_age: s.student_age,
          student_subject: s.student_subject,
          message_count: count(m.id),
          last_active: max(m.inserted_at),
          first_user_content:
            fragment(
              "COALESCE(LEFT(MIN(CASE WHEN ? = 'user' THEN ? END), 80), '')",
              m.role,
              m.content
            )
        }

    base_query =
      if search && search != "" do
        search_pattern = "%#{search}%"

        from [m, s] in base_query,
          where:
            ilike(s.student_name, ^search_pattern) or
              ilike(m.content, ^search_pattern)
      else
        base_query
      end

    total_count = count_branches(search)

    branches =
      base_query
      |> order_by([m], desc: max(m.inserted_at))
      |> offset(^((page - 1) * @per_page))
      |> limit(^@per_page)
      |> Repo.all()

    {branches, total_count}
  end

  @doc """
  Gets a session by chat_id. Returns nil if not found.
  """
  def get_session(chat_id) do
    Repo.get_by(Session, chat_id: chat_id)
  end

  @doc """
  Lists all audit messages for a specific branch within a chat,
  ordered by time.

  Returns a list of messages (not grouped, since we're looking at one branch).
  """
  def list_messages_for_branch(chat_id, branch_id) do
    Message
    |> where(chat_id: ^chat_id, branch_id: ^branch_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an audit session record. Called when a student starts a chat.
  """
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  defp count_branches(search) when is_nil(search) or search == "" do
    from(m in Message,
      select: count(fragment("(?, ?)", m.chat_id, m.branch_id), :distinct)
    )
    |> Repo.one()
  end

  defp count_branches(search) do
    search_pattern = "%#{search}%"

    from(m in Message,
      left_join: s in Session,
      on: m.chat_id == s.chat_id,
      where: ilike(s.student_name, ^search_pattern) or ilike(m.content, ^search_pattern),
      select: count(fragment("(?, ?)", m.chat_id, m.branch_id), :distinct)
    )
    |> Repo.one()
  end
end
