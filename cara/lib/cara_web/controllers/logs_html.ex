defmodule CaraWeb.LogsHTML do
  use CaraWeb, :html

  embed_templates "logs_html/*"

  def logs_url(page, search) do
    params = %{page: page}
    params = if search && search != "", do: Map.put(params, :q, search), else: params
    ~p"/logs?#{params}"
  end

  def branch_url(chat_id, branch_id) do
    ~p"/logs/#{chat_id}/#{branch_id}"
  end
end
