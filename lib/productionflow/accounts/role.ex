defmodule Productionflow.Accounts.Role do
  use Ecto.Schema
  import Ecto.Changeset

  alias Productionflow.Accounts.Permissions

  schema "roles" do
    field :name, :string
    field :description, :string
    field :permissions, {:array, :string}, default: []

    has_many :users, Productionflow.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :permissions])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> update_change(:permissions, &clean_permissions/1)
    |> validate_permissions()
    |> unique_constraint(:name)
  end

  # Checkbox forms submit empty strings and may repeat values; normalize before
  # validating so the stored array is clean.
  defp clean_permissions(nil), do: []

  defp clean_permissions(permissions) do
    permissions
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp validate_permissions(changeset) do
    validate_change(changeset, :permissions, fn :permissions, permissions ->
      case Enum.reject(permissions, &Permissions.valid?/1) do
        [] -> []
        invalid -> [permissions: "contains unknown permissions: #{Enum.join(invalid, ", ")}"]
      end
    end)
  end
end
