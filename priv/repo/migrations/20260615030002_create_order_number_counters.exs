defmodule Productionflow.Repo.Migrations.CreateOrderNumberCounters do
  use Ecto.Migration

  def change do
    create table(:order_number_counters) do
      add :scope, :string, null: false
      add :value, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:order_number_counters, [:scope])
  end
end
