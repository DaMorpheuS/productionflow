defmodule Productionflow.Inventory do
  @moduledoc """
  The Inventory context: a material catalog and a stock-movement ledger.

  Stock is never edited directly. Every purchase, consumption or adjustment is a
  signed `StockMovement`; the material's `current_stock` is kept in sync inside
  the same transaction (with the material row locked), so the invariant
  `current_stock == sum(movement.quantity)` always holds. A purchase with a unit
  cost also updates the material's `cost_price` (last-purchase-price).

  Negative stock is allowed (back-orders); callers warn via `negative_stock?/1`.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo

  alias Productionflow.Inventory.{
    Material,
    Category,
    StockMovement,
    MaterialType,
    FieldDefinition
  }

  ## Materials

  @doc """
  Lists materials ordered by name, preloading category and supplier.

  ## Options
    * `:search` - case-insensitive match on name, sku or supplier code
    * `:category_id` - restrict to a category
    * `:low_stock` - when true, only materials at/below their minimum stock
    * `:include_archived` - when true, also returns archived materials
  """
  def list_materials(opts \\ []) do
    Material
    |> filter_archived(Keyword.get(opts, :include_archived, false))
    |> filter_search(Keyword.get(opts, :search))
    |> filter_category(Keyword.get(opts, :category_id))
    |> filter_low_stock(Keyword.get(opts, :low_stock, false))
    |> order_by(asc: :name)
    |> preload([:category, :supplier])
    |> Repo.all()
  end

  defp filter_archived(query, true), do: query
  defp filter_archived(query, _), do: where(query, [m], is_nil(m.archived_at))

  defp filter_search(query, search) when search in [nil, ""], do: query

  defp filter_search(query, search) do
    like = "%#{String.replace(search, ~r/[%_]/, "")}%"

    where(
      query,
      [m],
      ilike(m.name, ^like) or ilike(m.sku, ^like) or ilike(m.supplier_code, ^like)
    )
  end

  defp filter_category(query, nil), do: query
  defp filter_category(query, ""), do: query
  defp filter_category(query, category_id), do: where(query, [m], m.category_id == ^category_id)

  defp filter_low_stock(query, true) do
    where(query, [m], not is_nil(m.minimum_stock) and m.current_stock <= m.minimum_stock)
  end

  defp filter_low_stock(query, _), do: query

  ## Dashboard aggregates

  @doc "Non-archived materials at or below their minimum, or in negative stock."
  def list_low_stock do
    low_stock_query()
    |> order_by(asc: :name)
    |> preload([:category, :supplier])
    |> Repo.all()
  end

  @doc "Counts the materials returned by `list_low_stock/0`."
  def count_low_stock do
    Repo.aggregate(low_stock_query(), :count, :id)
  end

  defp low_stock_query do
    from(m in Material,
      where:
        is_nil(m.archived_at) and
          ((not is_nil(m.minimum_stock) and m.current_stock <= m.minimum_stock) or
             m.current_stock < 0)
    )
  end

  @doc "Total value of stock on hand: Σ current_stock × cost_price over active materials."
  def total_stock_value do
    Repo.one(
      from(m in Material,
        where: is_nil(m.archived_at),
        select: coalesce(sum(m.current_stock * m.cost_price), 0)
      )
    )
  end

  @doc "Gets a material with category, supplier, type+fields and movements (newest first) preloaded."
  def get_material!(id) do
    movements =
      from(s in StockMovement, order_by: [desc: s.inserted_at, desc: s.id], preload: :user)

    Material
    |> Repo.get!(id)
    |> Repo.preload([
      :category,
      :supplier,
      [material_type: :field_definitions],
      movements: movements
    ])
  end

  @doc """
  Returns a changeset for a material, validating custom attributes against the
  field definitions of the given (or the material's current) type.
  """
  def change_material(material, attrs \\ %{}, field_definitions \\ nil)

  def change_material(%Material{} = material, attrs, nil) do
    Material.changeset(material, attrs, field_definitions_from_attrs(attrs, material))
  end

  def change_material(%Material{} = material, attrs, field_definitions) do
    Material.changeset(material, attrs, field_definitions)
  end

  @doc """
  Creates a material. An optional `"opening_stock"` (or `:opening_stock`) in
  `attrs` is booked as an initial adjustment movement in the same transaction.
  """
  def create_material(attrs) do
    {opening, attrs} = pop_opening_stock(attrs)
    field_definitions = field_definitions_from_attrs(attrs, %Material{})

    Repo.transact(fn ->
      with {:ok, material} <-
             %Material{} |> Material.changeset(attrs, field_definitions) |> Repo.insert() do
        maybe_book_opening(material, opening)
      end
    end)
  end

  defp maybe_book_opening(material, nil), do: {:ok, material}

  defp maybe_book_opening(material, opening) do
    if Decimal.equal?(opening, 0) do
      {:ok, material}
    else
      with {:ok, material} <-
             insert_movement(material, %{
               kind: :adjustment,
               quantity: opening,
               note: "Opening stock"
             }) do
        {:ok, material}
      end
    end
  end

  defp pop_opening_stock(attrs) do
    {raw, attrs} = pop_attr(attrs, "opening_stock", :opening_stock)

    case raw do
      nil -> {nil, attrs}
      "" -> {nil, attrs}
      value -> {dec(value), attrs}
    end
  end

  defp pop_attr(attrs, string_key, atom_key) do
    cond do
      Map.has_key?(attrs, string_key) -> Map.pop(attrs, string_key)
      Map.has_key?(attrs, atom_key) -> Map.pop(attrs, atom_key)
      true -> {nil, attrs}
    end
  end

  @doc "Updates a material's catalog fields (not its stock)."
  def update_material(%Material{} = material, attrs) do
    material
    |> Material.changeset(attrs, field_definitions_from_attrs(attrs, material))
    |> Repo.update()
  end

  # Resolves the field definitions for the type referenced by the incoming attrs,
  # falling back to the material's currently persisted type. Blank type → [].
  defp field_definitions_from_attrs(attrs, %Material{} = material) do
    case fetch(attrs, :material_type_id) do
      nil -> field_definitions_for(material.material_type_id)
      "" -> []
      id -> field_definitions_for(id)
    end
  end

  @doc "Archives a material."
  def archive_material(%Material{} = material) do
    material |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update()
  end

  @doc "Restores an archived material."
  def unarchive_material(%Material{} = material) do
    material |> Ecto.Changeset.change(archived_at: nil) |> Repo.update()
  end

  @doc "Hard-deletes a material and its movements (cascade)."
  def delete_material(%Material{} = material), do: Repo.delete(material)

  @doc "True when a minimum stock is set and current stock is at/below it."
  def low_stock?(%Material{minimum_stock: nil}), do: false

  def low_stock?(%Material{minimum_stock: min, current_stock: stock}),
    do: Decimal.compare(stock, min) != :gt

  @doc "True when current stock is below zero."
  def negative_stock?(%Material{current_stock: stock}), do: Decimal.compare(stock, 0) == :lt

  ## Categories

  @doc "Lists categories ordered by name."
  def list_categories, do: Category |> order_by(asc: :name) |> Repo.all()

  @doc "Returns a changeset for a category."
  def change_category(%Category{} = category, attrs \\ %{}),
    do: Category.changeset(category, attrs)

  @doc "Creates a category."
  def create_category(attrs), do: %Category{} |> Category.changeset(attrs) |> Repo.insert()

  @doc "Gets a category."
  def get_category!(id), do: Repo.get!(Category, id)

  @doc "Deletes a category (materials keep existing; their category is cleared)."
  def delete_category(%Category{} = category), do: Repo.delete(category)

  ## Material types & custom field definitions

  @doc "Lists material types ordered by name."
  def list_material_types, do: MaterialType |> order_by(asc: :name) |> Repo.all()

  @doc "Gets a material type with its field definitions (ordered) preloaded."
  def get_material_type!(id),
    do: MaterialType |> Repo.get!(id) |> Repo.preload(:field_definitions)

  @doc "Returns a changeset for a material type."
  def change_material_type(%MaterialType{} = type, attrs \\ %{}),
    do: MaterialType.changeset(type, attrs)

  @doc "Creates a material type."
  def create_material_type(attrs),
    do: %MaterialType{} |> MaterialType.changeset(attrs) |> Repo.insert()

  @doc "Updates a material type."
  def update_material_type(%MaterialType{} = type, attrs),
    do: type |> MaterialType.changeset(attrs) |> Repo.update()

  @doc "Deletes a material type (its field definitions cascade; materials keep existing)."
  def delete_material_type(%MaterialType{} = type), do: Repo.delete(type)

  @doc "Returns the field definitions of a type (ordered), or `[]` for a nil type."
  def field_definitions_for(nil), do: []

  def field_definitions_for(material_type_id) do
    from(f in FieldDefinition,
      where: f.material_type_id == ^material_type_id,
      order_by: [asc: f.position, asc: f.id]
    )
    |> Repo.all()
  end

  @doc "Gets a field definition."
  def get_field_definition!(id), do: Repo.get!(FieldDefinition, id)

  @doc "Returns a changeset for a field definition."
  def change_field_definition(%FieldDefinition{} = definition, attrs \\ %{}),
    do: FieldDefinition.changeset(definition, attrs)

  @doc "Adds a field definition to a material type."
  def create_field_definition(%MaterialType{} = type, attrs) do
    %FieldDefinition{material_type_id: type.id}
    |> FieldDefinition.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a field definition."
  def update_field_definition(%FieldDefinition{} = definition, attrs),
    do: definition |> FieldDefinition.changeset(attrs) |> Repo.update()

  @doc "Deletes a field definition."
  def delete_field_definition(%FieldDefinition{} = definition), do: Repo.delete(definition)

  ## Stock movements (booking)

  @doc """
  Receives stock (a purchase). Increases stock by `quantity`; when a positive
  `unit_cost` is given, also sets the material's `cost_price` to it.
  """
  def receive_stock(%Material{} = material, user, attrs) do
    quantity = attrs |> fetch(:quantity) |> dec()
    unit_cost = attrs |> fetch(:unit_cost) |> maybe_dec()

    insert_movement(
      material,
      %{
        kind: :purchase,
        quantity: Decimal.abs(quantity),
        unit_cost: unit_cost,
        note: fetch(attrs, :note)
      },
      user
    )
  end

  @doc """
  Consumes stock (a consumption). Decreases stock by `quantity`, which is allowed
  to push it below zero. (Order-driven consumption in M6 will call this too.)
  """
  def consume(%Material{} = material, user, attrs) do
    quantity = attrs |> fetch(:quantity) |> dec()

    insert_movement(
      material,
      %{
        kind: :consumption,
        quantity: Decimal.negate(Decimal.abs(quantity)),
        note: fetch(attrs, :note)
      },
      user
    )
  end

  @doc """
  Books a stock adjustment.

  Modes: `mode: :set` (or `"set"`) treats `quantity` as the counted amount and
  records the difference to current stock; `mode: :delta` records the signed
  `quantity` as-is. A zero net change records no movement.
  """
  def adjust(%Material{} = material, user, attrs) do
    mode = attrs |> fetch(:mode) |> to_mode()
    value = attrs |> fetch(:quantity) |> dec()
    note = fetch(attrs, :note)

    case mode do
      :set -> book_adjustment_to(material, value, note, user)
      :delta -> book_adjustment_delta(material, value, note, user)
    end
  end

  defp book_adjustment_to(material, counted, note, user) do
    book_movement(material, user, fn locked ->
      delta = Decimal.sub(counted, locked.current_stock)

      if Decimal.equal?(delta, 0),
        do: :noop,
        else: %{kind: :adjustment, quantity: delta, note: note}
    end)
  end

  defp book_adjustment_delta(material, delta, note, user) do
    if Decimal.equal?(delta, 0) do
      {:ok, material}
    else
      insert_movement(material, %{kind: :adjustment, quantity: delta, note: note}, user)
    end
  end

  defp to_mode(:delta), do: :delta
  defp to_mode("delta"), do: :delta
  defp to_mode(_), do: :set

  # Inserts a movement with a fixed attrs map.
  defp insert_movement(material, attrs, user \\ nil) do
    book_movement(material, user, fn _locked -> attrs end)
  end

  # Locks the material, lets `build_fn` compute the movement attrs from the
  # authoritative row (or return :noop), inserts the movement, and updates
  # current_stock (and cost_price for priced purchases) atomically.
  defp book_movement(material, user, build_fn) do
    Repo.transact(fn ->
      locked = lock_material(material.id)

      case build_fn.(locked) do
        :noop ->
          {:ok, locked}

        attrs ->
          attrs = Map.put(attrs, :user_id, user && user.id)

          with {:ok, movement} <- do_insert_movement(locked, attrs) do
            {:ok, apply_movement(locked, movement)}
          end
      end
    end)
  end

  defp lock_material(id) do
    from(m in Material, where: m.id == ^id, lock: "FOR UPDATE") |> Repo.one!()
  end

  defp do_insert_movement(material, attrs) do
    %StockMovement{material_id: material.id, user_id: attrs[:user_id]}
    |> StockMovement.changeset(attrs)
    |> Repo.insert()
  end

  defp apply_movement(material, movement) do
    new_stock = Decimal.add(material.current_stock, movement.quantity)
    changes = %{current_stock: new_stock}

    changes =
      if movement.kind == :purchase and priced?(movement.unit_cost),
        do: Map.put(changes, :cost_price, movement.unit_cost),
        else: changes

    material |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp priced?(nil), do: false
  defp priced?(%Decimal{} = cost), do: Decimal.compare(cost, 0) == :gt

  ## Attr/Decimal helpers

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp maybe_dec(nil), do: nil
  defp maybe_dec(""), do: nil
  defp maybe_dec(value), do: dec(value)

  defp dec(nil), do: Decimal.new(0)
  defp dec(%Decimal{} = d), do: d
  defp dec(value) when is_integer(value), do: Decimal.new(value)
  defp dec(value) when is_float(value), do: Decimal.from_float(value)

  defp dec(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _rest} -> decimal
      :error -> Decimal.new(0)
    end
  end
end
