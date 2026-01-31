defmodule Cara.AI.CLITest do
  use ExUnit.Case, async: true

  alias Cara.AI.CLI

  describe "start/1" do
    test "returns error when API key is not set" do
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      assert {:error, :missing_api_key} = CLI.start()

      if original_key do
        System.put_env("OPENROUTER_API_KEY", original_key)
      end
    end

    test "accepts custom model option" do
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      assert {:error, :missing_api_key} = CLI.start(model: "custom-model")

      if original_key do
        System.put_env("OPENROUTER_API_KEY", original_key)
      end
    end

    test "accepts custom system prompt option" do
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      assert {:error, :missing_api_key} = CLI.start(system_prompt: "Custom prompt")

      if original_key do
        System.put_env("OPENROUTER_API_KEY", original_key)
      end
    end

    test "accepts streaming option" do
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      assert {:error, :missing_api_key} = CLI.start(stream: false)

      if original_key do
        System.put_env("OPENROUTER_API_KEY", original_key)
      end
    end
  end
end
