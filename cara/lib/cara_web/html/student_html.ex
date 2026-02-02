defmodule CaraWeb.StudentHTML do
  @moduledoc """
  This module contains pages rendered by StudentController.

  See the `student_html` directory for all templates available.
  """
  use CaraWeb, :html

  embed_templates "student_html/*"
end
