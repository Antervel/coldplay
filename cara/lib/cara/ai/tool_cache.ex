defmodule Cara.AI.ToolCache do
  @moduledoc """
  Caching layer for AI tools.
  """
  alias Cara.AI.ToolResult
  alias Cara.Repo
  import Ecto.Query

  @doc """
  Retrieves a cached result for a tool call if it exists.
  """
  @spec get_result(String.t(), map() | list()) :: {:ok, String.t()} | :error
  def get_result(tool_name, args) do
    normalized_args = normalize_args(args)

    query =
      from tr in ToolResult,
        where: tr.tool_name == ^tool_name and tr.args == ^normalized_args,
        select: tr.result,
        order_by: [desc: tr.inserted_at, desc: tr.id],
        limit: 1

    case Repo.one(query) do
      nil -> :error
      result -> {:ok, result}
    end
  end

  @doc """
  Saves a tool execution result to the cache.
  """
  @spec save_result(String.t(), map() | list(), term()) :: {:ok, ToolResult.t()} | {:error, Ecto.Changeset.t()}
  def save_result(tool_name, args, result) do
    normalized_args = normalize_args(args)

    %ToolResult{}
    |> ToolResult.changeset(%{
      tool_name: tool_name,
      args: normalized_args,
      result: to_string(result)
    })
    |> Repo.insert()
  end

  defp normalize_args(args) when is_map(args) do
    # Convert all keys to strings for consistency in DB (JSONB)
    for {k, v} <- args, into: %{}, do: {to_string(k), v}
  end

  defp normalize_args(args) when is_list(args) do
    # If it's a list, wrap it in a map for JSONB column compatibility
    %{"_list" => args}
  end

  defp normalize_args(args) do
    # Wrap scalars in a map for Ecto JSONB compatibility
    %{"_value" => args}
  end
end
