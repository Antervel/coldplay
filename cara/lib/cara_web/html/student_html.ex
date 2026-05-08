defmodule CaraWeb.StudentHTML do
  @moduledoc """
  Provides HTML rendering for student pages.

  See the `student_html` directory for all templates available.
  """
  use CaraWeb, :html

  embed_templates "student_html/*"
end
