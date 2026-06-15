defmodule Productionflow.CatalogTest do
  use Productionflow.DataCase, async: true

  import Productionflow.CatalogFixtures
  import Productionflow.ProductionFixtures
  import Productionflow.InventoryFixtures

  alias Productionflow.Catalog
  alias Productionflow.Catalog.{ProductTemplate, CostEstimate}

  # A machine whose cost basis yields €4.00/hour: (10000/5 + 2000) / 1000.
  defp complete_machine(attrs \\ %{}) do
    machine_fixture(
      Enum.into(attrs, %{
        units_per_hour: Decimal.new(60),
        setup_minutes: Decimal.new(0),
        purchase_price: Decimal.new(10_000),
        lifetime_years: Decimal.new(5),
        yearly_maintenance_cost: Decimal.new(2_000),
        productive_hours_per_year: Decimal.new(1_000)
      })
    )
  end

  defp reload(template), do: Catalog.get_product_template!(template.id)

  describe "product templates" do
    test "create requires name and output_unit" do
      assert {:error, changeset} = Catalog.create_product_template(%{})
      assert %{name: ["can't be blank"], output_unit: ["can't be blank"]} = errors_on(changeset)
    end

    test "blank sku becomes nil, dup sku rejected" do
      assert {:ok, _} =
               Catalog.create_product_template(%{name: "A", output_unit: "item", sku: ""})

      assert {:ok, _} =
               Catalog.create_product_template(%{name: "B", output_unit: "item", sku: "P-1"})

      assert {:error, cs} =
               Catalog.create_product_template(%{name: "C", output_unit: "item", sku: "P-1"})

      assert %{sku: ["has already been taken"]} = errors_on(cs)
    end

    test "list filters by search and excludes archived" do
      a = product_template_fixture(%{name: "A5 flyer", sku: "FLY-A5"})
      archived = product_template_fixture(%{name: "Old poster"})
      {:ok, _} = Catalog.archive_product_template(archived)

      assert [found] = Catalog.list_product_templates(search: "flyer")
      assert found.id == a.id
      refute archived.id in Enum.map(Catalog.list_product_templates(), & &1.id)

      assert archived.id in Enum.map(
               Catalog.list_product_templates(include_archived: true),
               & &1.id
             )
    end
  end

  describe "route steps" do
    test "added steps get incrementing positions" do
      template = product_template_fixture()
      m = complete_machine()
      s1 = route_step_fixture(template, m)
      s2 = route_step_fixture(template, m)
      assert s2.position == s1.position + 1
    end

    test "store selected time modifier ids as integers" do
      template = product_template_fixture()
      machine = complete_machine()
      modifier = time_modifier_fixture(machine, %{kind: :percentage, value: Decimal.new(10)})

      {:ok, step} =
        Catalog.add_route_step(template, %{
          "machine_id" => machine.id,
          "quantity_per_unit" => "1",
          "time_modifier_ids" => ["", to_string(modifier.id)]
        })

      assert step.time_modifier_ids == [modifier.id]
    end
  end

  describe "estimate/2" do
    test "sums machine + material cost and duration for a quantity" do
      template = product_template_fixture()
      machine = complete_machine()
      material = material_fixture(%{cost_price: Decimal.new(2)})
      route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(1)})
      template_material_fixture(template, material, %{quantity_per_unit: Decimal.new("0.25")})

      est = Catalog.estimate(reload(template), 60)
      assert %CostEstimate{} = est
      # 60 units / 60 per hour = 1 hour = 60 minutes
      assert Decimal.equal?(est.duration_minutes, Decimal.new("60"))
      assert Decimal.equal?(est.machine_cost, Decimal.new("4"))
      # 60 × 0.25 = 15 units × €2 = €30
      assert Decimal.equal?(est.material_cost, Decimal.new("30"))
      assert Decimal.equal?(est.total_cost, Decimal.new("34"))
      # unit cost = 34 / 60
      assert Decimal.equal?(est.unit_cost, Decimal.div(Decimal.new("34"), Decimal.new("60")))
    end

    test "scales machine quantity by the per-step factor" do
      template = product_template_fixture()
      machine = complete_machine()
      route_step_fixture(template, machine, %{quantity_per_unit: Decimal.new(2)})

      est = Catalog.estimate(reload(template), 10)
      # 10 × 2 = 20 units / 60 per hour = 20 minutes
      assert Decimal.equal?(est.duration_minutes, Decimal.new("20"))
    end

    test "applies material waste percentage" do
      template = product_template_fixture()
      material = material_fixture(%{cost_price: Decimal.new(1)})

      template_material_fixture(template, material, %{
        quantity_per_unit: Decimal.new(1),
        waste_pct: Decimal.new(10)
      })

      est = Catalog.estimate(reload(template), 100)
      # 100 × 1 × 1.10 = 110 × €1
      assert Decimal.equal?(est.material_cost, Decimal.new("110"))
    end

    test "sums durations across multiple steps" do
      template = product_template_fixture()
      m = complete_machine(%{units_per_hour: Decimal.new(60)})
      route_step_fixture(template, m, %{quantity_per_unit: Decimal.new(1)})
      route_step_fixture(template, m, %{quantity_per_unit: Decimal.new(1)})

      est = Catalog.estimate(reload(template), 60)
      # two steps × 60 minutes
      assert Decimal.equal?(est.duration_minutes, Decimal.new("120"))
    end

    test "nil-poisons machine and total cost when a step's machine cost basis is incomplete" do
      template = product_template_fixture()
      complete = complete_machine()
      incomplete = machine_fixture(%{units_per_hour: Decimal.new(60)})
      material = material_fixture(%{cost_price: Decimal.new(2)})
      route_step_fixture(template, complete)
      route_step_fixture(template, incomplete)
      template_material_fixture(template, material, %{quantity_per_unit: Decimal.new(1)})

      est = Catalog.estimate(reload(template), 10)
      assert est.machine_cost == nil
      assert est.total_cost == nil
      assert est.unit_cost == nil
      # material cost still computed
      assert Decimal.equal?(est.material_cost, Decimal.new("20"))
    end

    test "unit cost is nil for a zero quantity without crashing" do
      template = product_template_fixture()
      route_step_fixture(template, complete_machine())
      est = Catalog.estimate(reload(template), 0)
      assert est.unit_cost == nil
    end
  end

  describe "referential integrity" do
    test "a referenced machine cannot be hard-deleted" do
      template = product_template_fixture()
      machine = complete_machine()
      route_step_fixture(template, machine)

      assert_raise Ecto.ConstraintError, fn ->
        Productionflow.Production.delete_machine(machine)
      end
    end

    test "a referenced material cannot be hard-deleted" do
      template = product_template_fixture()
      material = material_fixture()
      template_material_fixture(template, material)

      assert_raise Ecto.ConstraintError, fn ->
        Productionflow.Inventory.delete_material(material)
      end
    end

    test "deleting a template cascades its route and BoM" do
      template = product_template_fixture()
      machine = complete_machine()
      material = material_fixture()
      step = route_step_fixture(template, machine)
      line = template_material_fixture(template, material)

      assert {:ok, _} = Catalog.delete_product_template(%ProductTemplate{id: template.id})
      assert Repo.get(Productionflow.Catalog.RouteStep, step.id) == nil
      assert Repo.get(Productionflow.Catalog.TemplateMaterial, line.id) == nil
    end
  end
end
