defmodule Cara.AI.Tools.SilverBullet do
  require Logger

  @moduledoc """
  A module containing tools to interact with SilverBullet wiki.
  """
  alias Cara.SilverBullet
  alias ReqLLM.Tool

  def silver_bullet_get do
    Tool.new!(
      name: "silver_bullet_get",
      description: "Get the content of a SilverBullet wiki page by title. Input: {\"title\": \"Page Title\"}",
      parameter_schema: [
        title: [type: :string, required: true, doc: "The title of the page to retrieve"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)
        title = args[:title] || args["title"]

        result =
          case SilverBullet.get_page(title) do
            {:ok, content} ->
              {:ok, "Content of '#{title}':\n#{content}"}

            {:error, reason} ->
              {:error, "Failed to retrieve SilverBullet page: #{reason}"}
          end

        end_time = :erlang.monotonic_time(:millisecond)
        Logger.info("Tool 'silver_bullet_get' total execution took #{end_time - start_time}ms")
        result
      end
    )
  end

  def silver_bullet_save do
    Tool.new!(
      name: "silver_bullet_save",
      description:
        "Save a summary or content to a SilverBullet wiki page. Input: {\"title\": \"Page Title\", \"content\": \"Markdown content\"}",
      parameter_schema: [
        title: [type: :string, required: true, doc: "The title of the page to save"],
        content: [type: :string, required: true, doc: "The markdown content to save"]
      ],
      callback: fn args ->
        start_time = :erlang.monotonic_time(:millisecond)
        title = args[:title] || args["title"]
        content = args[:content] || args["content"]

        result =
          case SilverBullet.save_page(title, content) do
            :ok ->
              {:ok, "Successfully saved content to SilverBullet page '#{title}'."}

            {:error, reason} ->
              {:error, "Failed to save SilverBullet page: #{reason}"}
          end

        end_time = :erlang.monotonic_time(:millisecond)
        Logger.info("Tool 'silver_bullet_save' total execution took #{end_time - start_time}ms")
        result
      end
    )
  end
end
