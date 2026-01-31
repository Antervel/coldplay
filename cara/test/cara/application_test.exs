defmodule Cara.ApplicationTest do
  use ExUnit.Case, async: true

  alias Cara.Application

  test "application supervisor is running" do
    assert Process.whereis(Cara.Supervisor) != nil
  end

  test "config_change/3" do
    assert :ok = Application.config_change([], [], [])
  end
end
