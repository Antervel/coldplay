defmodule Cara.Audit do
  @moduledoc """
  Context module for auditing student chat sessions and messages.

  Provides functions to create sessions, list branches (unique chat_id +
  branch_id pairs), and retrieve messages for a specific branch.
  """

  alias Cara.Audit.Message
  alias Cara.Audit.Session
  alias Cara.Repo

  import Ecto.Query

  @per_page 50

  @doc """
  Creates an audit session for a student chat.
  """
  @spec create_session(map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a session by chat_id.
  """
  @spec get_session(String.t()) :: Session.t() | nil
  def get_session(chat_id) do
    Repo.get_by(Session, chat_id: chat_id)
  end

  @doc """
  Lists unique (chat_id, branch_id) pairs with student info, message count,
  and a content preview from the first user message.

  ## Options

    * `:search` — filters by student name or message content (case-insensitive)
    * `:page` — page number (1-based, default 1)

  Returns `{branches, total_count}` where each branch is a map with keys
  `:chat_id`, `:branch_id`, `:student_name`, `:student_age`,
  `:student_subject`, `:message_count`, `:first_user_content`, and
  `:last_active`.
  """
  @spec list_branches(keyword()) :: {list(map()), integer()}
  def list_branches(opts \\ []) do
    search = Keyword.get(opts, :search)
    page = Keyword.get(opts, :page, 1)
    offset = (max(page, 1) - 1) * @per_page

    base_query =
      from m in Message,
        group_by: [m.chat_id, m.branch_id],
        select: %{
          chat_id: m.chat_id,
          branch_id: m.branch_id,
          message_count: count(m.id),
          first_user_content:
            fragment(
              "COALESCE((SELECT m2.content FROM audit_messages m2 WHERE m2.chat_id = ? AND m2.branch_id = ? AND m2.role = 'user' ORDER BY m2.inserted_at ASC LIMIT 1), '')",
              m.chat_id,
              m.branch_id
            ),
          last_active: max(m.inserted_at)
        }

    filtered_query =
      if search do
        term = "%#{search}%"

        matching_chat_ids =
          from s in Session,
            where: ilike(s.student_name, ^term),
            select: s.chat_id

        matching_content_chat_ids =
          from msg in Message,
            where: ilike(msg.content, ^term),
            select: msg.chat_id,
            distinct: true

        from m in base_query,
          having:
            m.chat_id in subquery(matching_chat_ids) or
              m.chat_id in subquery(matching_content_chat_ids)
      else
        base_query
      end

    total =
      from(q in subquery(filtered_query), select: count(q.chat_id))
      |> Repo.one()

    branches_query =
      from b in subquery(filtered_query),
        left_join: s in Session,
        on: b.chat_id == s.chat_id,
        select: %{
          chat_id: b.chat_id,
          branch_id: b.branch_id,
          student_name: s.student_name,
          student_age: s.student_age,
          student_subject: s.student_subject,
          message_count: b.message_count,
          first_user_content: b.first_user_content,
          last_active: b.last_active
        },
        order_by: [desc: s.inserted_at],
        limit: ^@per_page,
        offset: ^offset

    branches = Repo.all(branches_query)
    {branches, total}
  end

  @doc """
  Lists all audit messages for a specific chat branch, ordered by inserted_at.
  """
  @spec list_messages_for_branch(String.t(), String.t()) :: [Message.t()]
  def list_messages_for_branch(chat_id, branch_id) do
    query =
      from m in Message,
        where: m.chat_id == ^chat_id and m.branch_id == ^branch_id,
        order_by: [asc: m.inserted_at]

    Repo.all(query)
  end
end
