defmodule Cara.SilverBullet do
  require Logger

  @moduledoc """
  A module to interface with the SilverBullet wiki API.
  """

  defp http_client do
    Application.get_env(:cara, :http_client, Req)
  end

  defp base_url do
    config = Application.get_env(:cara, :silver_bullet, [])
    config[:base_url] || "http://localhost:3000"
  end

  defp auth_token do
    config = Application.get_env(:cara, :silver_bullet, [])
    config[:auth_token]
  end

  defp headers do
    [
      {"Authorization", "Bearer " <> auth_token()},
      {"Content-Type", "text/markdown"}
    ]
  end

  @doc """
  Retrieves a page from SilverBullet.
  """
  @spec get_page(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_page(title) do
    start_time = :erlang.monotonic_time(:millisecond)
    path = ensure_md_extension(title)

    result =
      case http_client().get("#{base_url()}/.fs/#{URI.encode(path)}", headers: headers()) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: 404}} ->
          {:error, "Page not found"}

        {:ok, %{status: status}} ->
          {:error, "HTTP error: #{status}"}

        {:error, reason} ->
          {:error, reason}
      end

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("SilverBullet get_page('#{title}') took #{end_time - start_time}ms")
    result
  end

  @doc """
  Saves a page to SilverBullet.
  """
  @spec save_page(String.t(), String.t()) :: :ok | {:error, term()}
  def save_page(title, content) do
    start_time = :erlang.monotonic_time(:millisecond)
    path = ensure_md_extension(title)

    result =
      case http_client().put("#{base_url()}/.fs/#{URI.encode(path)}",
             body: content,
             headers: headers()
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} ->
          {:error, "HTTP error: #{status}"}

        {:error, reason} ->
          {:error, reason}
      end

    end_time = :erlang.monotonic_time(:millisecond)
    Logger.info("SilverBullet save_page('#{title}') took #{end_time - start_time}ms")
    result
  end

  defp ensure_md_extension(title) do
    if String.ends_with?(title, ".md") do
      title
    else
      "#{title}.md"
    end
  end
end
