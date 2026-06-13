defmodule Productionflow.Repo.Migrations.CreateRelations do
  use Ecto.Migration

  def change do
    create table(:relations) do
      add :name, :string, null: false
      add :code, :string
      add :is_customer, :boolean, null: false, default: false
      add :is_supplier, :boolean, null: false, default: false
      add :is_prospect, :boolean, null: false, default: false
      add :email, :string
      add :phone, :string
      add :website, :string
      add :vat_number, :string
      add :iban, :string
      add :remarks, :text
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relations, [:code], where: "code IS NOT NULL")
  end
end
