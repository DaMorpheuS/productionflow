defmodule Productionflow.Production do
  @moduledoc """
  The Production context: machines, their per-machine time modifiers, the
  organization energy setting, and the generic time + internal-cost engine.

  Time for a job on a machine is `setup + quantity / units_per_hour`, optionally
  increased by selected time modifiers. Internal cost combines the derived
  machine cost (write-off + maintenance over productive hours), labour (the sum
  of the assigned operators' hourly cost) and energy (power draw × tariff).

  All money/quantity math uses `Decimal`; derived per-hour costs are computed on
  the fly and never stored, and rounding happens only at display time.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo

  alias Productionflow.Accounts.User
  alias Productionflow.Production.{Machine, TimeModifier, Settings, Estimate}

  ## Machines

  @doc """
  Lists machines ordered by name.

  ## Options
    * `:search` - case-insensitive match on name
    * `:include_archived` - when true, also returns archived machines
  """
  def list_machines(opts \\ []) do
    Machine
    |> filter_archived(Keyword.get(opts, :include_archived, false))
    |> filter_search(Keyword.get(opts, :search))
    |> order_by(asc: :name)
    |> preload([:operators, :time_modifiers])
    |> Repo.all()
  end

  defp filter_archived(query, true), do: query
  defp filter_archived(query, _), do: where(query, [m], is_nil(m.archived_at))

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    like = "%#{String.replace(search, ~r/[%_]/, "")}%"
    where(query, [m], ilike(m.name, ^like))
  end

  @doc "Counts non-archived machines."
  def count_machines do
    Repo.aggregate(from(m in Machine, where: is_nil(m.archived_at)), :count, :id)
  end

  @doc "Gets a machine with operators and time modifiers preloaded."
  def get_machine!(id) do
    Machine
    |> Repo.get!(id)
    |> Repo.preload([:operators, :time_modifiers])
  end

  @doc "Returns a changeset for a machine (operators come from `change_machine/3`)."
  def change_machine(%Machine{} = machine, attrs \\ %{}) do
    Machine.changeset(machine, attrs)
  end

  @doc """
  Returns a changeset including operator assignment, for live form validation.
  """
  def change_machine(%Machine{} = machine, attrs, operator_ids) do
    Machine.changeset(machine, attrs, load_operators(operator_ids))
  end

  @doc "Creates a machine, assigning the given operator ids."
  def create_machine(attrs, operator_ids \\ []) do
    %Machine{operators: []}
    |> Machine.changeset(attrs, load_operators(operator_ids))
    |> Repo.insert()
  end

  @doc "Updates a machine, replacing its operators with the given ids."
  def update_machine(%Machine{} = machine, attrs, operator_ids \\ []) do
    machine
    |> Repo.preload(:operators)
    |> Machine.changeset(attrs, load_operators(operator_ids))
    |> Repo.update()
  end

  @doc "Archives a machine."
  def archive_machine(%Machine{} = machine) do
    machine
    |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  @doc "Restores an archived machine."
  def unarchive_machine(%Machine{} = machine) do
    machine
    |> Ecto.Changeset.change(archived_at: nil)
    |> Repo.update()
  end

  @doc "Hard-deletes a machine and its modifiers/operator links (cascade)."
  def delete_machine(%Machine{} = machine), do: Repo.delete(machine)

  defp load_operators(ids) do
    ids = ids |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))
    if ids == [], do: [], else: Repo.all(from(u in User, where: u.id in ^ids))
  end

  ## Time modifiers

  @doc "Adds a time modifier to a machine."
  def add_time_modifier(%Machine{} = machine, attrs) do
    %TimeModifier{machine_id: machine.id}
    |> TimeModifier.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a changeset for a new time modifier (for the inline form)."
  def change_time_modifier(attrs \\ %{}) do
    TimeModifier.changeset(%TimeModifier{}, attrs)
  end

  @doc "Gets a time modifier."
  def get_time_modifier!(id), do: Repo.get!(TimeModifier, id)

  @doc "Deletes a time modifier."
  def delete_time_modifier(%TimeModifier{} = modifier), do: Repo.delete(modifier)

  ## Settings (singleton)

  @doc "Returns the production settings, creating the singleton row if missing."
  def get_settings do
    Repo.get(Settings, 1) || create_default_settings()
  end

  defp create_default_settings do
    %Settings{id: 1}
    |> Settings.changeset(%{energy_price_per_kwh: Decimal.new(0)})
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    Repo.get!(Settings, 1)
  end

  @doc "Returns a changeset for the settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc "Updates the production settings."
  def update_settings(attrs) do
    get_settings()
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  ## Cost & time engine

  @doc """
  Machine cost per hour, derived from write-off and maintenance over the
  productive hours per year. Returns `nil` when the cost basis is incomplete
  (no positive lifetime or productive hours).
  """
  def machine_cost_per_hour(%Machine{} = machine) do
    with {:ok, lifetime} <- positive(machine.lifetime_years),
         {:ok, hours} <- positive(machine.productive_hours_per_year) do
      write_off_per_year =
        machine.purchase_price
        |> dec()
        |> Decimal.sub(dec(machine.residual_value))
        |> Decimal.div(lifetime)

      write_off_per_year
      |> Decimal.add(dec(machine.yearly_maintenance_cost))
      |> Decimal.div(hours)
    else
      :error -> nil
    end
  end

  @doc "Labour cost per hour: the sum of the assigned operators' hourly cost."
  def labour_cost_per_hour(%Machine{} = machine) do
    machine
    |> operators()
    |> Enum.reduce(Decimal.new(0), fn user, acc -> Decimal.add(acc, dec(user.hourly_cost)) end)
  end

  @doc "Energy cost per hour: power draw × the organization energy tariff."
  def energy_cost_per_hour(%Machine{} = machine, %Settings{} = settings) do
    Decimal.mult(dec(machine.power_kw), dec(settings.energy_price_per_kwh))
  end

  @doc """
  Internal cost per hour = machine + labour + energy. Returns `nil` if the
  machine cost is undefined (incomplete cost basis).
  """
  def internal_cost_per_hour(%Machine{} = machine, %Settings{} = settings) do
    case machine_cost_per_hour(machine) do
      nil ->
        nil

      machine_cost ->
        machine_cost
        |> Decimal.add(labour_cost_per_hour(machine))
        |> Decimal.add(energy_cost_per_hour(machine, settings))
    end
  end

  @doc """
  Estimates duration and internal cost for producing `quantity` units on a
  machine, applying the selected time modifiers (by id).

  Returns a `Productionflow.Production.Estimate`. `machine_cost`/`total_cost`
  are `nil` when the machine's cost basis is incomplete.
  """
  def estimate(%Machine{} = machine, quantity, modifier_ids \\ []) do
    settings = get_settings()
    qty = dec(quantity)

    base_minutes =
      machine.setup_minutes
      |> dec()
      |> Decimal.add(Decimal.mult(Decimal.div(qty, machine.units_per_hour), Decimal.new(60)))

    total_minutes = apply_modifiers(base_minutes, machine, modifier_ids)
    hours = Decimal.div(total_minutes, Decimal.new(60))

    labour_cost = Decimal.mult(hours, labour_cost_per_hour(machine))
    energy_cost = Decimal.mult(hours, energy_cost_per_hour(machine, settings))

    machine_cost =
      case machine_cost_per_hour(machine) do
        nil -> nil
        rate -> Decimal.mult(hours, rate)
      end

    total_cost =
      if machine_cost,
        do: machine_cost |> Decimal.add(labour_cost) |> Decimal.add(energy_cost),
        else: nil

    %Estimate{
      duration_minutes: total_minutes,
      machine_cost: machine_cost,
      labour_cost: labour_cost,
      energy_cost: energy_cost,
      total_cost: total_cost
    }
  end

  defp apply_modifiers(base_minutes, machine, modifier_ids) do
    ids = modifier_ids |> List.wrap() |> Enum.map(&to_string/1)
    selected = Enum.filter(modifiers(machine), &(to_string(&1.id) in ids))

    {percent, fixed} =
      Enum.reduce(selected, {Decimal.new(0), Decimal.new(0)}, fn mod, {pct, fix} ->
        case mod.kind do
          :percentage -> {Decimal.add(pct, dec(mod.value)), fix}
          :fixed_minutes -> {pct, Decimal.add(fix, dec(mod.value))}
        end
      end)

    multiplier = Decimal.add(Decimal.new(1), Decimal.div(percent, Decimal.new(100)))

    base_minutes
    |> Decimal.mult(multiplier)
    |> Decimal.add(fixed)
  end

  defp operators(%Machine{operators: %Ecto.Association.NotLoaded{}} = machine),
    do: Repo.preload(machine, :operators).operators

  defp operators(%Machine{operators: operators}), do: operators

  defp modifiers(%Machine{time_modifiers: %Ecto.Association.NotLoaded{}} = machine),
    do: Repo.preload(machine, :time_modifiers).time_modifiers

  defp modifiers(%Machine{time_modifiers: modifiers}), do: modifiers

  # Treats nil as 0 for arithmetic; ensures a Decimal.
  defp dec(nil), do: Decimal.new(0)
  defp dec(%Decimal{} = d), do: d
  defp dec(other), do: Decimal.new(to_string(other))

  # Returns {:ok, decimal} when the value is a positive number, else :error.
  defp positive(nil), do: :error

  defp positive(value) do
    d = dec(value)
    if Decimal.compare(d, 0) == :gt, do: {:ok, d}, else: :error
  end
end
