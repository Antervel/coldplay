defmodule Cara.Hooks.SilverBullet do
  require Logger

  @moduledoc """
  A SilverBullet hook.
  """

  def on_exit(socket) do
    Logger.info("Exit! #{inspect(socket.assigns)}")
  end
end
