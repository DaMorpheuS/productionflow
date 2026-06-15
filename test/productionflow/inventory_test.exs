defmodule Productionflow.InventoryTest do
  use Productionflow.DataCase, async: true

  import Productionflow.InventoryFixtures
  import Productionflow.AccountsFixtures
  import Productionflow.CRMFixtures

  alias Productionflow.Inventory
  alias Productionflow.Inventory.{Material, Category}

  describe "create_material/1" do
    test "creates a material" do
      assert {:ok, %Material{} = m} = Inventory.create_material(%{name: "Ink", unit: "L"})
      assert m.name == "Ink"
      assert Decimal.equal?(m.current_stock, 0)
    end

    test "requires name and unit" do
      assert {:error, changeset} = Inventory.create_material(%{})
      assert %{name: ["can't be blank"], unit: ["can't be blank"]} = errors_on(changeset)
    end

    test "normalizes blank sku to nil and enforces uniqueness when present" do
      assert {:ok, _} = Inventory.create_material(%{name: "A", unit: "x", sku: ""})
      assert {:ok, _} = Inventory.create_material(%{name: "B", unit: "x", sku: "  "})
      assert {:ok, _} = Inventory.create_material(%{name: "C", unit: "x", sku: "SKU-1"})

      assert {:error, changeset} =
               Inventory.create_material(%{name: "D", unit: "x", sku: "SKU-1"})

      assert %{sku: ["has already been taken"]} = errors_on(changeset)
    end

    test "books an opening stock as one adjustment movement" do
      assert {:ok, material} =
               Inventory.create_material(%{name: "Paper", unit: "sheet", opening_stock: "500"})

      material = Inventory.get_material!(material.id)
      assert Decimal.equal?(material.current_stock, 500)
      assert [%{kind: :adjustment} = mv] = material.movements
      assert Decimal.equal?(mv.quantity, 500)
    end

    test "links supplier and category" do
      supplier = relation_fixture(%{is_customer: false, is_supplier: true})
      category = category_fixture()

      assert {:ok, material} =
               Inventory.create_material(%{
                 name: "Bolt",
                 unit: "pieces",
                 supplier_id: supplier.id,
                 category_id: category.id,
                 supplier_code: "EXT-9"
               })

      assert material.supplier_id == supplier.id
      assert material.category_id == category.id
      assert material.supplier_code == "EXT-9"
    end
  end

  describe "list_materials/1" do
    test "filters by search across name, sku and supplier code" do
      a = material_fixture(%{name: "Blue ink", sku: "INK-B"})
      b = material_fixture(%{name: "Red paint", supplier_code: "RP-99"})

      assert [found] = Inventory.list_materials(search: "blue")
      assert found.id == a.id
      assert [by_sku] = Inventory.list_materials(search: "ink-b")
      assert by_sku.id == a.id
      assert [by_code] = Inventory.list_materials(search: "rp-99")
      assert by_code.id == b.id
    end

    test "filters by category and low stock and excludes archived" do
      category = category_fixture()
      _other = material_fixture()
      in_cat = material_fixture(%{category_id: category.id, minimum_stock: "10"})

      assert [found] = Inventory.list_materials(category_id: category.id)
      assert found.id == in_cat.id

      # in_cat has 0 stock, minimum 10 -> low
      assert [low] = Inventory.list_materials(low_stock: true)
      assert low.id == in_cat.id

      {:ok, _} = Inventory.archive_material(in_cat)
      refute in_cat.id in Enum.map(Inventory.list_materials(), & &1.id)
      assert in_cat.id in Enum.map(Inventory.list_materials(include_archived: true), & &1.id)
    end
  end

  describe "receive_stock/3" do
    test "increases stock and updates cost price to the unit cost" do
      user = user_fixture()
      material = material_fixture(%{cost_price: "1.00"})

      {:ok, material} =
        Inventory.receive_stock(material, user, %{quantity: "100", unit_cost: "2.50"})

      assert Decimal.equal?(material.current_stock, 100)
      assert Decimal.equal?(material.cost_price, "2.50")
    end

    test "leaves cost price untouched when no unit cost is given" do
      material = material_fixture(%{cost_price: "1.00"})
      {:ok, material} = Inventory.receive_stock(material, nil, %{quantity: "10"})
      assert Decimal.equal?(material.cost_price, "1.00")
      assert Decimal.equal?(material.current_stock, 10)
    end
  end

  describe "consume/3" do
    test "decreases stock and may go negative" do
      material = material_fixture()
      {:ok, material} = Inventory.consume(material, nil, %{quantity: "5"})
      assert Decimal.equal?(material.current_stock, -5)
      assert Inventory.negative_stock?(material)
    end
  end

  describe "adjust/3" do
    test ":set mode records the difference to current stock" do
      material = material_fixture(%{opening_stock: "20"})
      {:ok, material} = Inventory.adjust(material, nil, %{mode: :set, quantity: "30"})
      assert Decimal.equal?(material.current_stock, 30)

      material = Inventory.get_material!(material.id)
      # opening (20) + set-to-30 delta (10)
      assert [latest | _] = material.movements
      assert Decimal.equal?(latest.quantity, 10)
    end

    test ":delta mode stores the signed value" do
      material = material_fixture(%{opening_stock: "20"})
      {:ok, material} = Inventory.adjust(material, nil, %{mode: :delta, quantity: "-3"})
      assert Decimal.equal?(material.current_stock, 17)
    end

    test "records no movement when set to the current value" do
      material = material_fixture(%{opening_stock: "20"})
      count_before = length(Inventory.get_material!(material.id).movements)

      {:ok, material} = Inventory.adjust(material, nil, %{mode: :set, quantity: "20"})
      assert Decimal.equal?(material.current_stock, 20)
      assert length(Inventory.get_material!(material.id).movements) == count_before
    end
  end

  test "current_stock equals the sum of movement quantities" do
    user = user_fixture()
    material = material_fixture(%{opening_stock: "100"})
    {:ok, _} = Inventory.receive_stock(material, user, %{quantity: "50", unit_cost: "1"})
    material = Inventory.get_material!(material.id)
    {:ok, _} = Inventory.consume(material, user, %{quantity: "30"})
    material = Inventory.get_material!(material.id)
    {:ok, _} = Inventory.adjust(material, user, %{mode: :delta, quantity: "-5"})

    material = Inventory.get_material!(material.id)
    sum = Enum.reduce(material.movements, Decimal.new(0), &Decimal.add(&2, &1.quantity))
    assert Decimal.equal?(material.current_stock, sum)
    assert Decimal.equal?(material.current_stock, 115)
  end

  describe "categories" do
    test "create, list and delete nilifies materials' category" do
      category = category_fixture(%{name: "Inks"})
      material = material_fixture(%{category_id: category.id})

      assert Enum.map(Inventory.list_categories(), & &1.name) == ["Inks"]

      assert {:ok, _} = Inventory.delete_category(category)
      assert Inventory.get_material!(material.id).category_id == nil
    end

    test "enforces unique names" do
      category_fixture(%{name: "Dup"})
      assert {:error, changeset} = Inventory.create_category(%{name: "Dup"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
      assert %Category{} = Productionflow.Repo.get_by(Category, name: "Dup")
    end
  end

  test "inventory.book implies inventory.view" do
    assert "inventory.view" in Productionflow.Accounts.Permissions.expand(["inventory.book"])
  end
end
