defmodule Cara.AI.PromptTest do
  use ExUnit.Case, async: true

  alias Cara.AI.Prompt

  describe "render/2" do
    test "renders a prompt template with assigns" do
      rendered = Prompt.render("test_prompt", %{name: "World"})
      assert rendered == "Hello, World!"
    end

    test "raises an error if the template doesn't exist" do
      assert_raise File.Error, fn ->
        Prompt.render("non_existent_template", %{})
      end
    end
  end
end
