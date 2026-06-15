defmodule Productionflow.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :number, :string, null: false
      add :relation_id, references(:relations, on_delete: :restrict), null: false
      add :reference, :string
      add :status, :string, null: false, default: "draft"
      add :order_date, :date, null: false
      add :due_date, :date
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:number])
    create index(:orders, [:relation_id])
    create index(:orders, [:status])
  end
end
