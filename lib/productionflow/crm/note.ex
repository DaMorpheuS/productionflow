defmodule Productionflow.CRM.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :body, :string

    belongs_to :relation, Productionflow.CRM.Relation
    belongs_to :user, Productionflow.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body])
    |> validate_required([:body])
  end
end
