defmodule Productionflow.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :relation_id, references(:relations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notes, [:relation_id])
    create index(:notes, [:user_id])
  end
end
