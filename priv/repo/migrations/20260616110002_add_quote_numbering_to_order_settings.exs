defmodule Productionflow.Repo.Migrations.AddQuoteNumberingToOrderSettings do
  use Ecto.Migration

  def change do
    alter table(:order_settings) do
      add :quote_number_mode, :string, null: false, default: "per_year"
      add :quote_number_prefix, :string, null: false, default: "QUO"
    end
  end
end
