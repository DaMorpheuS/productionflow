defmodule Productionflow.InventoryTypesTest do
  use Productionflow.DataCase, async: true

  import Productionflow.InventoryFixtures

  alias Productionflow.Inventory
  alias Productionflow.Inventory.{MaterialType, FieldDefinition}

  describe "material types" do
    test "create requires a unique name" do
      assert {:ok, %MaterialType{name: "Sheet paper"}} =
               Inventory.create_material_type(%{name: "Sheet paper"})

      assert {:error, changeset} = Inventory.create_material_type(%{name: "Sheet paper"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "delete cascades field definitions but keeps materials" do
      type = material_type_fixture()
      _def = field_definition_fixture(type, %{key: "grammage", field_type: :number})
      material = material_fixture(%{material_type_id: type.id})

      assert {:ok, _} = Inventory.delete_material_type(type)
      assert Inventory.field_definitions_for(type.id) == []
      assert Inventory.get_material!(material.id).material_type_id == nil
    end
  end

  describe "field definitions" do
    setup do
      %{type: material_type_fixture()}
    end

    test "key must be a slug and unique within the type", %{type: type} do
      assert {:ok, %FieldDefinition{}} =
               Inventory.create_field_definition(type, %{
                 key: "thickness",
                 label: "Thickness",
                 field_type: :number
               })

      assert {:error, cs} =
               Inventory.create_field_definition(type, %{
                 key: "Thickness!",
                 label: "X",
                 field_type: :text
               })

      assert errors_on(cs)[:key]

      assert {:error, dup} =
               Inventory.create_field_definition(type, %{
                 key: "thickness",
                 label: "Dup",
                 field_type: :text
               })

      assert errors_on(dup)[:key]
    end

    test "select fields require options", %{type: type} do
      assert {:error, cs} =
               Inventory.create_field_definition(type, %{
                 key: "coating",
                 label: "Coating",
                 field_type: :select
               })

      assert errors_on(cs)[:options]

      assert {:ok, def} =
               Inventory.create_field_definition(type, %{
                 key: "coating",
                 label: "Coating",
                 field_type: :select,
                 options: "gloss, matte ,, silk"
               })

      assert def.options == ["gloss", "matte", "silk"]
    end

    test "field_definitions_for returns ordered list", %{type: type} do
      field_definition_fixture(type, %{key: "b", position: 2})
      field_definition_fixture(type, %{key: "a", position: 1})

      assert ["a", "b"] = Enum.map(Inventory.field_definitions_for(type.id), & &1.key)
    end
  end

  describe "material custom attributes" do
    setup do
      type = material_type_fixture(%{name: "Sheet paper"})

      field_definition_fixture(type, %{
        key: "grammage",
        label: "Grammage",
        field_type: :number,
        unit: "g/m²"
      })

      field_definition_fixture(type, %{
        key: "coating",
        label: "Coating",
        field_type: :select,
        options: ["gloss", "matte"]
      })

      field_definition_fixture(type, %{key: "fsc", label: "FSC", field_type: :boolean})

      field_definition_fixture(type, %{
        key: "note",
        label: "Note",
        field_type: :text,
        required: true
      })

      %{type: type}
    end

    test "coerces and stores values by field type", %{type: type} do
      {:ok, material} =
        Inventory.create_material(%{
          name: "Coated 90g",
          unit: "sheet",
          material_type_id: type.id,
          attributes: %{
            "grammage" => "90",
            "coating" => "gloss",
            "fsc" => "true",
            "note" => "House stock"
          }
        })

      assert material.attributes == %{
               "grammage" => "90",
               "coating" => "gloss",
               "fsc" => true,
               "note" => "House stock"
             }
    end

    test "rejects a number and an out-of-range select, and requires required fields", %{
      type: type
    } do
      assert {:error, changeset} =
               Inventory.create_material(%{
                 name: "Bad",
                 unit: "sheet",
                 material_type_id: type.id,
                 attributes: %{"grammage" => "heavy", "coating" => "neon", "note" => ""}
               })

      errored_keys =
        for {:attributes, {_msg, opts}} <- changeset.errors, do: opts[:key]

      assert "grammage" in errored_keys
      assert "coating" in errored_keys
      assert "note" in errored_keys
    end

    test "prunes attributes not defined by the type", %{type: type} do
      {:ok, material} =
        Inventory.create_material(%{
          name: "Pruned",
          unit: "sheet",
          material_type_id: type.id,
          attributes: %{"grammage" => "120", "note" => "x", "bogus" => "drop me"}
        })

      refute Map.has_key?(material.attributes, "bogus")
      assert material.attributes["grammage"] == "120"
    end

    test "clearing the type empties attributes", %{type: type} do
      {:ok, material} =
        Inventory.create_material(%{
          name: "Typed",
          unit: "sheet",
          material_type_id: type.id,
          attributes: %{"grammage" => "120", "note" => "x"}
        })

      {:ok, material} = Inventory.update_material(material, %{material_type_id: ""})
      assert material.material_type_id == nil
      assert material.attributes == %{}
    end
  end
end
