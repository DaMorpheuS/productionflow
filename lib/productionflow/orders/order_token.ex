defmodule Productionflow.Orders.OrderToken do
  @moduledoc """
  Hashed, expiring tokens for the public quote accept/decline link. Mirrors the
  `Accounts.UserToken` scheme (random bytes, sha256-hashed at rest), but tied to
  an order rather than a user.
  """

  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32
  @validity_in_days 30

  schema "order_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :order, Productionflow.Orders.Order

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Builds `{url_token, struct}`: the struct (with the hashed token) is inserted."
  def build_token(order, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed, context: context, sent_to: sent_to, order_id: order.id}}
  end

  @doc "Query that returns the order for a valid, unexpired token in `context`."
  def verify_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)

        query =
          from t in __MODULE__,
            join: o in assoc(t, :order),
            where:
              t.token == ^hashed and t.context == ^context and
                t.inserted_at > ago(@validity_in_days, "day"),
            select: o

        {:ok, query}

      :error ->
        :error
    end
  end
end
