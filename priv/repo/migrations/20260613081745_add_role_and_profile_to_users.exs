defmodule Productionflow.Repo.Migrations.AddRoleAndProfileToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :active, :boolean, null: false, default: true
      add :role_id, references(:roles, on_delete: :restrict)
    end

    create index(:users, [:role_id])
  end
end
