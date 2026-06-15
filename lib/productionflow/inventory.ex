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

  alias Productionflow.Inventory.{Material, Category, StockMovement}

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

  @doc "Gets a material with category, supplier and movements (newest first) preloaded."
  def get_material!(id) do
    movements =
      from(s in StockMovement, order_by: [desc: s.inserted_at, desc: s.id], preload: :user)

    Material
    |> Repo.get!(id)
    |> Repo.preload([:category, :supplier, movements: movements])
  end

  @doc "Returns a changeset for a material."
  def change_material(%Material{} = material, attrs \\ %{}) do
    Material.changeset(material, attrs)
  end

  @doc """
  Creates a material. An optional `"opening_stock"` (or `:opening_stock`) in
  `attrs` is booked as an initial adjustment movement in the same transaction.
  """
  def create_material(attrs) do
    {opening, attrs} = pop_opening_stock(attrs)

    Repo.transact(fn ->
      with {:ok, material} <- %Material{} |> Material.changeset(attrs) |> Repo.insert() do
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
    |> Material.changeset(attrs)
    |> Repo.update()
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
