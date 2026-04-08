defmodule Cara.AI.Tools do
  @moduledoc """
  Manager for LLM tools. Loads tools from configuration.
  """

  alias Cara.AI.Tools.Calculator
  alias Cara.AI.Tools.SilverBullet
  alias Cara.AI.Tools.Wikipedia

  @doc """
  Loads the list of enabled tools based on application configuration.

  Default tools:
  - `calculator`: Cara.AI.Tools.Calculator.calculator_tool/0
  - `wikipedia_search`: Cara.AI.Tools.Wikipedia.wikipedia_search/0
  - `wikipedia_get_article`: Cara.AI.Tools.Wikipedia.wikipedia_get_article/0
  - `silver_bullet_get`: Cara.AI.Tools.SilverBullet.silver_bullet_get/0
  - `silver_bullet_save`: Cara.AI.Tools.SilverBullet.silver_bullet_save/0
  """
  @spec load_tools() :: list(ReqLLM.Tool.t())
  def load_tools do
    enabled_tools =
      Application.get_env(:cara, :enabled_tools, [
        :calculator,
        :wikipedia_search,
        :wikipedia_get_article,
        :silver_bullet_get,
        :silver_bullet_save
      ])

    Enum.map(enabled_tools, &instantiate_tool/1)
  end

  defp instantiate_tool(:calculator), do: Calculator.calculator_tool()
  defp instantiate_tool(:wikipedia_search), do: Wikipedia.wikipedia_search()
  defp instantiate_tool(:wikipedia_get_article), do: Wikipedia.wikipedia_get_article()
  defp instantiate_tool(:silver_bullet_get), do: SilverBullet.silver_bullet_get()
  defp instantiate_tool(:silver_bullet_save), do: SilverBullet.silver_bullet_save()
  defp instantiate_tool(tool_name) when is_binary(tool_name), do: instantiate_tool(String.to_existing_atom(tool_name))
end
