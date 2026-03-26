defmodule Cara.AI.ToolResult do
  @moduledoc """
  Schema for storing tool execution results.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tool_results" do
    field :tool_name, :string
    field :args, :map
    field :result, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          tool_name: String.t(),
          args: map(),
          result: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(tool_result, attrs) do
    tool_result
    |> cast(attrs, [:tool_name, :args, :result])
    |> validate_required([:tool_name, :args, :result])
  end
end
