defmodule CaraWeb.LogsHTML do
  use CaraWeb, :html

  embed_templates "logs_html/*"

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :current_sort, :atom, required: true
  attr :current_dir, :atom, required: true
  attr :search, :any, default: nil
  attr :page, :integer, default: 1

  def sort_header(assigns) do
    field_atom = String.to_atom(assigns.field)
    active? = field_atom == assigns.current_sort

    next_dir =
      cond do
        not active? -> :asc
        assigns.current_dir == :asc -> :desc
        true -> :asc
      end

    icon =
      cond do
        not active? -> "hero-arrows-up-down"
        assigns.current_dir == :asc -> "hero-arrow-up"
        true -> "hero-arrow-down"
      end

    assigns =
      assign(assigns,
        active?: active?,
        next_dir: next_dir,
        icon: icon,
        href: sort_url(assigns.field, next_dir, assigns.search, assigns.page)
      )

    ~H"""
    <.link href={@href} class="inline-flex items-center gap-1 group">
      {@label}
      <.icon
        name={@icon}
        class={[
          "w-3.5 h-3.5 transition-colors",
          @active? && "text-indigo-600",
          !@active? && "text-gray-400 group-hover:text-gray-600"
        ]}
      />
    </.link>
    """
  end

  defp sort_url(field, dir, search, page) do
    params = %{"sort_by" => field, "sort_dir" => Atom.to_string(dir), "page" => page}
    params = if search && search != "", do: Map.put(params, "q", search), else: params
    ~p"/logs?#{params}"
  end

  def logs_url(page, search, sort_by \\ :date, sort_dir \\ :desc) do
    params = %{page: page, sort_by: Atom.to_string(sort_by), sort_dir: Atom.to_string(sort_dir)}
    params = if search && search != "", do: Map.put(params, :q, search), else: params
    ~p"/logs?#{params}"
  end

  def branch_url(chat_id, branch_id) do
    ~p"/logs/#{chat_id}/#{branch_id}"
  end
end
