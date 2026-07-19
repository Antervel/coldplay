defmodule Cara.HTTPClient do
  @moduledoc """
  Wraps Req HTTP client calls so context modules don't depend on Req directly.
  """

  # credo:disable-for-this-file Credo.Check.Extra.NoDirectThirdPartyCalls
  def get(url, opts \\ []) do
    Req.new(opts)
    |> OpentelemetryReq.attach(no_path_params: true)
    |> Req.get(url: url)
  end

  def post(url, opts \\ []) do
    Req.new(opts)
    |> OpentelemetryReq.attach(no_path_params: true)
    |> Req.post(url: url)
  end
end
