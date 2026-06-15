defmodule Productionflow.Repo.Migrations.AddMarginPctToProductTemplates do
  use Ecto.Migration

  def change do
    alter table(:product_templates) do
      add :margin_pct, :decimal, precision: 12, scale: 4
    end
  end
end
