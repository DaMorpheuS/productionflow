defmodule Productionflow.Repo.Migrations.CreateOrderLineDependencies do
  use Ecto.Migration

  # A line may depend on other lines of the same order: each must be done before
  # the dependent line can be produced. Self-referential many-to-many; no
  # timestamps (join table, per convention).
  def change do
    create table(:order_line_dependencies, primary_key: false) do
      add :order_line_id, references(:order_lines, on_delete: :delete_all), null: false
      add :depends_on_id, references(:order_lines, on_delete: :delete_all), null: false
    end

    create unique_index(:order_line_dependencies, [:order_line_id, :depends_on_id])
    create index(:order_line_dependencies, [:depends_on_id])
  end
end
