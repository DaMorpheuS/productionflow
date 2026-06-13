defmodule Productionflow.Repo.Migrations.CreateAddresses do
  use Ecto.Migration

  def change do
    create table(:addresses) do
      add :relation_id, references(:relations, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :street, :string
      add :postal_code, :string
      add :city, :string
      add :country, :string
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:addresses, [:relation_id])
  end
end
