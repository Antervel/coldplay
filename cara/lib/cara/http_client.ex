defmodule Cara.HTTPClient do
  @moduledoc """
  Wraps Req HTTP client calls so context modules don't depend on Req directly.
  """

  # credo:disable-for-this-file Credo.Check.Extra.NoDirectThirdPartyCalls
  def get(url, opts \\ []) do
    opts
    |> Req.new()
    |> OpentelemetryReq.attach(no_path_params: true)
    # credo:disable-for-next-line
    |> Req.get(url: url)
  end

  def post(url, opts \\ []) do
    opts
    |> Req.new()
    |> OpentelemetryReq.attach(no_path_params: true)
    # credo:disable-for-next-line
    |> Req.post(url: url)
  end
end
