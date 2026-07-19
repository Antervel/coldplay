defmodule CaraWeb.PageController do
  use CaraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def sleeping(conn, _params) do
    render(conn, :sleeping)
  end

  def settings(conn, _params) do
    current_model = Application.get_env(:cara, :ai_model, "openai:openai/gpt-oss-20b")
    render(conn, :settings, current_model: current_model)
  end

  def update_model(conn, %{"model" => model}) do
    Application.put_env(:cara, :ai_model, model)
    apply_model_config(model)

    conn
    |> put_flash(:info, "Model updated to #{model}")
    |> redirect(to: ~p"/settings")
  end

  defp apply_model_config("openai:openai/gpt-oss-20b") do
    Application.put_env(:branched_llm, :base_url, "https://integrate.api.nvidia.com/v1")
    Application.put_env(:req_llm, :openai_api_key, System.get_env("NVIDIA_API_KEY", ""))

    Application.put_env(:req_llm, :openai,
      base_url: "https://integrate.api.nvidia.com/v1",
      api_key: System.get_env("NVIDIA_API_KEY", "nvidia")
    )
  end

  defp apply_model_config(_) do
    Application.put_env(:branched_llm, :base_url, "http://host.containers.internal:11434/v1")
    Application.put_env(:req_llm, :openai_api_key, "ollama")

    Application.put_env(:req_llm, :openai,
      base_url: "http://host.containers.internal:11434/v1",
      api_key: "ollama"
    )
  end
end
