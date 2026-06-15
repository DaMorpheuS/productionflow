defmodule Productionflow.Repo.Migrations.CreatePriceLists do
  use Ecto.Migration

  def change do
    create table(:price_lists) do
      add :name, :string, null: false
      add :relation_id, references(:relations, on_delete: :nilify_all)
      add :active, :boolean, null: false, default: true
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:price_lists, [:name])
    create index(:price_lists, [:relation_id])
  end
end
