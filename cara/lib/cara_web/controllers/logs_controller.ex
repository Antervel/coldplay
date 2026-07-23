defmodule CaraWeb.LogsController do
  use CaraWeb, :controller

  alias Cara.Audit

  @per_page 50

  plug :put_root_layout, html: {CaraWeb.Layouts, :logs}
  plug :put_layout, false

  def index(conn, params) do
    search = params["q"]
    page = parse_page(params["page"])
    sort_by = parse_sort(params["sort_by"])
    sort_dir = parse_sort_dir(params["sort_dir"])

    {branches, total_count} =
      Audit.list_branches(search: search, page: page, sort_by: sort_by, sort_dir: sort_dir)

    total_pages = ceil(total_count / @per_page)

    render(conn, :index,
      branches: branches,
      search: search,
      page: page,
      total_pages: total_pages,
      total_count: total_count,
      sort_by: sort_by,
      sort_dir: sort_dir
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

  @valid_sort_fields ~W(date student subject messages)
  defp parse_sort(nil), do: :date
  defp parse_sort(str) when str in @valid_sort_fields, do: String.to_atom(str)
  defp parse_sort(_), do: :date

  @valid_sort_dirs ~W(asc desc)
  defp parse_sort_dir(nil), do: :desc
  defp parse_sort_dir(str) when str in @valid_sort_dirs, do: String.to_atom(str)
  defp parse_sort_dir(_), do: :desc
end
