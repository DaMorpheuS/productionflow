defmodule Productionflow.Repo.Migrations.AddQuoteFieldsToOrders do
  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :quote_number, :string
      add :valid_until, :date
      add :decline_reason, :string
      add :decline_notes, :text
      add :archived_at, :utc_datetime
      add :archive_reason, :text
      modify :number, :string, null: true, from: {:string, null: false}
    end

    # Unify the status model: the old :confirmed order state is now :accepted.
    execute("UPDATE orders SET status = 'accepted' WHERE status = 'confirmed'")
    # Backfill a quote number for existing documents.
    execute("UPDATE orders SET quote_number = number WHERE quote_number IS NULL")

    create unique_index(:orders, [:quote_number])
  end

  def down do
    drop unique_index(:orders, [:quote_number])
    execute("UPDATE orders SET status = 'confirmed' WHERE status = 'accepted'")

    alter table(:orders) do
      remove :quote_number
      remove :valid_until
      remove :decline_reason
      remove :decline_notes
      remove :archived_at
      remove :archive_reason
      modify :number, :string, null: false
    end
  end
end
