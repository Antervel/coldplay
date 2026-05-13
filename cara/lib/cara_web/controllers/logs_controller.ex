defmodule CaraWeb.LogsController do
  use CaraWeb, :controller

  alias Cara.Audit

  @per_page 50

  def index(conn, params) do
    search = params["q"]
    page = parse_page(params["page"])

    {branches, total_count} = Audit.list_branches(search: search, page: page)
    total_pages = ceil(total_count / @per_page)

    render(conn, :index,
      branches: branches,
      search: search,
      page: page,
      total_pages: total_pages,
      total_count: total_count
    )
  end

  def show(conn, %{"chat_id" => chat_id, "branch_id" => branch_id}) do
    session = Audit.get_session(chat_id)
    messages = Audit.list_messages_for_branch(chat_id, branch_id)

    if messages == [] do
      conn
      |> put_status(:not_found)
      |> put_view(html: CaraWeb.ErrorHTML)
      |> render(:"404")
    else
      render(conn, :show,
        session: session,
        messages: messages,
        chat_id: chat_id,
        branch_id: branch_id
      )
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
