defmodule Productionflow.Repo do
  use Ecto.Repo,
    otp_app: :productionflow,
    adapter: Ecto.Adapters.Postgres
end
