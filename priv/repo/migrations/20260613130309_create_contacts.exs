defmodule Productionflow.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :relation_id, references(:relations, on_delete: :delete_all), null: false
      add :address_id, references(:addresses, on_delete: :nilify_all)
      add :name, :string, null: false
      add :job_title, :string
      add :email, :string
      add :phone, :string
      add :remarks, :text

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:relation_id])
    create index(:contacts, [:address_id])
  end
end
