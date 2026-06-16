defmodule Productionflow.Repo.Migrations.CreateOrderTokens do
  use Ecto.Migration

  def change do
    create table(:order_tokens) do
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :order_id, references(:orders, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:order_tokens, [:order_id])
    create unique_index(:order_tokens, [:context, :token])
  end
end
