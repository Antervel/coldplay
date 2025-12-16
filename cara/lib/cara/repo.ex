defmodule Cara.Repo do
  use Ecto.Repo,
    otp_app: :cara,
    adapter: Ecto.Adapters.Postgres
end
