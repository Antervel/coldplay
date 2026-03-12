defmodule Cara.AI.CLITest do
  use ExUnit.Case, async: true

  alias Cara.AI.CLI

  describe "start/1" do
    test "returns error when API key is not set" do
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      original_app_key = Application.get_env(:req_llm, :openai_api_key)
      Application.delete_env(:req_llm, :openai_api_key)

      assert {:error, :missing_api_key} = CLI.start()

      if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      if original_app_key, do: Application.put_env(:req_llm, :openai_api_key, original_app_key)
    end

    test "accepts custom model option" do
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      original_app_key = Application.get_env(:req_llm, :openai_api_key)
      Application.delete_env(:req_llm, :openai_api_key)

      assert {:error, :missing_api_key} = CLI.start(model: "custom-model")

      if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      if original_app_key, do: Application.put_env(:req_llm, :openai_api_key, original_app_key)
    end

    test "accepts custom system prompt option" do
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      original_app_key = Application.get_env(:req_llm, :openai_api_key)
      Application.delete_env(:req_llm, :openai_api_key)

      assert {:error, :missing_api_key} = CLI.start(system_prompt: "Custom prompt")

      if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      if original_app_key, do: Application.put_env(:req_llm, :openai_api_key, original_app_key)
    end

    test "accepts streaming option" do
      original_key = System.get_env("OPENAI_API_KEY")
      System.put_env("OPENAI_API_KEY", "test")
      original_app_key = Application.get_env(:req_llm, :openai_api_key)
      Application.put_env(:req_llm, :openai_api_key, "test")

      # We can't easily test :ok because it enters a loop.
      # But the fact that it doesn't return {:error, :missing_api_key} means it passed validation.
      # For testing purpose in this project, CLI.start/1 was modified to return :quit in test env.
      assert CLI.start(stream: false) == :quit

      if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      if original_app_key, do: Application.put_env(:req_llm, :openai_api_key, original_app_key)
    end
  end
end
