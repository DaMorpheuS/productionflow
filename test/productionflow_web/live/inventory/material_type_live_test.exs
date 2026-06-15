defmodule ProductionflowWeb.Inventory.MaterialTypeLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.InventoryFixtures

  alias Productionflow.Inventory

  describe "authorization" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.view"]
    test "view-only users cannot reach material types", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/inventory/types")
    end
  end

  describe "type management" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.manage"]
    test "creates a type, adds a field, and deletes the field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/inventory/types/new")
      lv |> form("#type-form", material_type: %{name: "Sheet paper"}) |> render_submit()

      type = Enum.find(Inventory.list_material_types(), &(&1.name == "Sheet paper"))
      assert_redirect(lv, ~p"/inventory/types/#{type}")

      {:ok, lv, _html} = live(conn, ~p"/inventory/types/#{type}/fields/new")

      lv
      |> form("#field-form",
        field_definition: %{
          key: "grammage",
          label: "Grammage",
          field_type: "number",
          unit: "g/m²"
        }
      )
      |> render_submit()

      assert_redirect(lv, ~p"/inventory/types/#{type}")
      [field] = Inventory.get_material_type!(type.id).field_definitions
      assert field.key == "grammage"

      {:ok, lv, _html} = live(conn, ~p"/inventory/types/#{type}")
      assert has_element?(lv, "#fields", "Grammage")
      lv |> element("#fields a", "Delete") |> render_click()
      refute has_element?(lv, "#fields", "Grammage")
    end

    @tag permissions: ["inventory.manage"]
    test "shows option input only for select fields", %{conn: conn} do
      type = material_type_fixture()
      {:ok, lv, html} = live(conn, ~p"/inventory/types/#{type}/fields/new")
      refute html =~ "field_definition_options"

      html =
        lv
        |> form("#field-form",
          field_definition: %{label: "Coating", key: "coating", field_type: "select"}
        )
        |> render_change()

      assert html =~ "field_definition_options"
    end
  end

  describe "custom fields on the material form" do
    setup [:register_and_log_in_user]

    setup do
      type = material_type_fixture(%{name: "Sheet paper"})

      field_definition_fixture(type, %{
        key: "grammage",
        label: "Grammage",
        field_type: :number,
        unit: "g/m²"
      })

      field_definition_fixture(type, %{
        key: "note",
        label: "Note",
        field_type: :text,
        required: true
      })

      %{type: type}
    end

    @tag permissions: ["inventory.manage"]
    test "renders custom inputs after picking a type and saves values", %{conn: conn, type: type} do
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/new")

      html =
        lv
        |> form("#material-form",
          material: %{name: "Coated", unit: "sheet", material_type_id: type.id}
        )
        |> render_change()

      assert html =~ "material_attr_grammage"
      assert html =~ "material_attr_note"

      lv
      |> form("#material-form",
        material: %{
          name: "Coated",
          unit: "sheet",
          material_type_id: type.id,
          attributes: %{"grammage" => "90", "note" => "House"}
        }
      )
      |> render_submit()

      material = Enum.find(Inventory.list_materials(), &(&1.name == "Coated"))
      assert material

      assert Inventory.get_material!(material.id).attributes == %{
               "grammage" => "90",
               "note" => "House"
             }
    end

    @tag permissions: ["inventory.manage"]
    test "shows an inline error for a missing required custom field", %{conn: conn, type: type} do
      {:ok, lv, _html} = live(conn, ~p"/inventory/materials/new")

      # Pick the type first so the custom field inputs render.
      lv
      |> form("#material-form", material: %{name: "X", unit: "sheet", material_type_id: type.id})
      |> render_change()

      html =
        lv
        |> form("#material-form",
          material: %{
            name: "X",
            unit: "sheet",
            material_type_id: type.id,
            attributes: %{"grammage" => "90", "note" => ""}
          }
        )
        |> render_submit()

      assert html =~ "is required"
    end
  end

  describe "material show" do
    setup [:register_and_log_in_user]

    @tag permissions: ["inventory.view"]
    test "displays custom attributes", %{conn: conn} do
      type = material_type_fixture(%{name: "Sheet paper"})

      field_definition_fixture(type, %{
        key: "grammage",
        label: "Grammage",
        field_type: :number,
        unit: "g/m²"
      })

      {:ok, material} =
        Inventory.create_material(%{
          name: "Coated 90",
          unit: "sheet",
          material_type_id: type.id,
          attributes: %{"grammage" => "90"}
        })

      {:ok, _lv, html} = live(conn, ~p"/inventory/materials/#{material}")
      assert html =~ "Grammage"
      assert html =~ "90"
    end
  end
end
