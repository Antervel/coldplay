defmodule CaraWeb.PageHTML do
  @moduledoc """
  Provides HTML rendering for static pages.

  See the `page_html` directory for all templates available.
  """
  use CaraWeb, :html

  embed_templates "page_html/*"
end
