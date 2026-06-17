defmodule Productionflow.ProductionTest do
  use Productionflow.DataCase, async: true

  import Productionflow.ProductionFixtures
  import Productionflow.AccountsFixtures

  alias Productionflow.Production
  alias Productionflow.Production.{Machine, Settings, Estimate}

  defp operator_with_cost(cost) do
    user = user_fixture()
    Repo.update!(Ecto.Changeset.change(user, hourly_cost: Decimal.new(cost)))
  end

  defp reload(machine), do: Production.get_machine!(machine.id)

  describe "create_machine/2" do
    test "creates a machine with required fields" do
      assert {:ok, %Machine{} = machine} =
               Production.create_machine(%{
                 name: "Laser",
                 output_unit: "m",
                 units_per_hour: Decimal.new(120)
               })

      assert machine.name == "Laser"
      assert machine.operators == []
    end

    test "requires name, output_unit and a positive units_per_hour" do
      assert {:error, changeset} = Production.create_machine(%{units_per_hour: Decimal.new(0)})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:output_unit]
      assert errors[:units_per_hour]
    end

    test "assigns operators by id" do
      u1 = operator_with_cost("30")
      u2 = operator_with_cost("20")

      {:ok, machine} =
        Production.create_machine(
          %{name: "Press", output_unit: "pieces", units_per_hour: Decimal.new(100)},
          [u1.id, u2.id]
        )

      machine = Production.get_machine!(machine.id)
      assert Enum.map(machine.operators, & &1.id) |> Enum.sort() == Enum.sort([u1.id, u2.id])
    end

    test "defaults working hours to a Mon–Fri 08:00–16:30 day" do
      {:ok, machine} =
        Production.create_machine(%{
          name: "Laser",
          output_unit: "m",
          units_per_hour: Decimal.new(120)
        })

      assert machine.working_day_start == ~T[08:00:00]
      assert machine.working_day_end == ~T[16:30:00]
      assert machine.working_days == [1, 2, 3, 4, 5]
    end

    test "casts working-day strings and rejects the blank sentinel" do
      {:ok, machine} =
        Production.create_machine(%{
          "name" => "Press",
          "output_unit" => "pieces",
          "units_per_hour" => "100",
          "working_day_start" => "06:00",
          "working_day_end" => "22:00",
          "working_days" => ["", "1", "3", "5"]
        })

      assert machine.working_day_start == ~T[06:00:00]
      assert machine.working_day_end == ~T[22:00:00]
      assert machine.working_days == [1, 3, 5]
    end

    test "rejects an end before the start, no working days, or an unknown day" do
      assert {:error, cs} =
               Production.create_machine(%{
                 name: "Press",
                 output_unit: "pieces",
                 units_per_hour: Decimal.new(100),
                 working_day_start: ~T[16:00:00],
                 working_day_end: ~T[08:00:00],
                 working_days: []
               })

      assert errors_on(cs)[:working_day_end]
      assert errors_on(cs)[:working_days]

      assert {:error, cs2} =
               Production.create_machine(%{
                 name: "Press",
                 output_unit: "pieces",
                 units_per_hour: Decimal.new(100),
                 working_days: [1, 9]
               })

      assert errors_on(cs2)[:working_days]
    end
  end

  describe "update_machine/3" do
    test "replaces the operator set" do
      u1 = operator_with_cost("30")
      u2 = operator_with_cost("20")
      machine = machine_fixture(%{}, [u1.id, u2.id])

      {:ok, _} = Production.update_machine(machine, %{name: machine.name}, [u1.id])

      machine = Production.get_machine!(machine.id)
      assert Enum.map(machine.operators, & &1.id) == [u1.id]
    end
  end

  describe "list_machines/1" do
    test "filters by search and excludes archived by default" do
      laser = machine_fixture(%{name: "Laser cutter"})
      _press = machine_fixture(%{name: "Offset press"})
      archived = machine_fixture(%{name: "Old guillotine"})
      {:ok, _} = Production.archive_machine(archived)

      assert [found] = Production.list_machines(search: "laser")
      assert found.id == laser.id

      ids = Production.list_machines() |> Enum.map(& &1.id)
      refute archived.id in ids
      assert archived.id in Enum.map(Production.list_machines(include_archived: true), & &1.id)
    end
  end

  describe "machine_cost_per_hour/1" do
    test "derives from write-off + maintenance over productive hours" do
      machine =
        machine_fixture(%{
          purchase_price: Decimal.new(10_000),
          residual_value: Decimal.new(0),
          lifetime_years: Decimal.new(5),
          yearly_maintenance_cost: Decimal.new(2_000),
          productive_hours_per_year: Decimal.new(1_000)
        })

      # (10000/5 + 2000) / 1000 = 4.0
      assert Decimal.equal?(Production.machine_cost_per_hour(machine), Decimal.new("4"))
    end

    test "is nil when lifetime or productive hours are missing or zero" do
      assert Production.machine_cost_per_hour(machine_fixture(%{productive_hours_per_year: nil})) ==
               nil

      assert Production.machine_cost_per_hour(
               machine_fixture(%{
                 lifetime_years: nil,
                 productive_hours_per_year: Decimal.new(1000)
               })
             ) == nil
    end
  end

  describe "labour_cost_per_hour/1" do
    test "sums the assigned operators' hourly cost" do
      u1 = operator_with_cost("30")
      u2 = operator_with_cost("20")
      machine = machine_fixture(%{}, [u1.id, u2.id]) |> reload()

      assert Decimal.equal?(Production.labour_cost_per_hour(machine), Decimal.new("50"))
    end

    test "is zero with no operators" do
      machine = machine_fixture() |> reload()
      assert Decimal.equal?(Production.labour_cost_per_hour(machine), Decimal.new("0"))
    end
  end

  describe "estimate/3" do
    setup do
      u1 = operator_with_cost("30")
      u2 = operator_with_cost("20")
      set_energy_price(Decimal.new("0.30"))

      machine =
        machine_fixture(
          %{
            units_per_hour: Decimal.new(60),
            setup_minutes: Decimal.new(0),
            power_kw: Decimal.new(2),
            purchase_price: Decimal.new(10_000),
            lifetime_years: Decimal.new(5),
            yearly_maintenance_cost: Decimal.new(2_000),
            productive_hours_per_year: Decimal.new(1_000)
          },
          [u1.id, u2.id]
        )
        |> reload()

      %{machine: machine}
    end

    test "computes duration and cost breakdown for one hour of work", %{machine: machine} do
      est = Production.estimate(machine, 60)
      assert %Estimate{} = est
      assert Decimal.equal?(est.duration_minutes, Decimal.new("60"))
      assert Decimal.equal?(est.machine_cost, Decimal.new("4"))
      assert Decimal.equal?(est.labour_cost, Decimal.new("50"))
      assert Decimal.equal?(est.energy_cost, Decimal.new("0.60"))
      assert Decimal.equal?(est.total_cost, Decimal.new("54.60"))
    end

    test "applies a percentage modifier to time and cost", %{machine: machine} do
      modifier = time_modifier_fixture(machine, %{kind: :percentage, value: Decimal.new(10)})
      machine = Production.get_machine!(machine.id)

      est = Production.estimate(machine, 60, [modifier.id])
      # 60 * 1.10 = 66 minutes
      assert Decimal.equal?(est.duration_minutes, Decimal.new("66"))
      # 1.1h * 50 labour = 55
      assert Decimal.equal?(est.labour_cost, Decimal.new("55"))
    end

    test "applies a fixed-minutes modifier", %{machine: machine} do
      modifier = time_modifier_fixture(machine, %{kind: :fixed_minutes, value: Decimal.new(15)})
      machine = Production.get_machine!(machine.id)

      est = Production.estimate(machine, 60, [modifier.id])
      assert Decimal.equal?(est.duration_minutes, Decimal.new("75"))
    end

    test "leaves machine/total cost nil when cost basis is incomplete" do
      machine = machine_fixture(%{units_per_hour: Decimal.new(60)}) |> reload()
      est = Production.estimate(machine, 60)
      assert est.machine_cost == nil
      assert est.total_cost == nil
      # labour/energy still computed
      assert Decimal.equal?(est.labour_cost, Decimal.new("0"))
    end
  end

  describe "settings" do
    test "get_settings returns the seeded singleton" do
      assert %Settings{id: 1} = Production.get_settings()
    end

    test "update_settings changes the energy price" do
      {:ok, settings} = Production.update_settings(%{energy_price_per_kwh: Decimal.new("0.42")})
      assert Decimal.equal?(settings.energy_price_per_kwh, Decimal.new("0.42"))
      assert Decimal.equal?(Production.get_settings().energy_price_per_kwh, Decimal.new("0.42"))
    end
  end

  describe "time modifiers" do
    test "add and delete" do
      machine = machine_fixture()

      {:ok, modifier} =
        Production.add_time_modifier(machine, %{name: "Complex", value: Decimal.new(20)})

      assert Production.get_machine!(machine.id).time_modifiers |> length() == 1

      {:ok, _} = Production.delete_time_modifier(modifier)
      assert Production.get_machine!(machine.id).time_modifiers == []
    end

    test "requires name and value" do
      machine = machine_fixture()
      assert {:error, changeset} = Production.add_time_modifier(machine, %{name: ""})
      assert errors_on(changeset)[:name]
      assert errors_on(changeset)[:value]
    end
  end
end
