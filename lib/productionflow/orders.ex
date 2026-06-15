defmodule Productionflow.Orders do
  @moduledoc """
  The Orders context: customer production orders built from the rest of the
  system. An order belongs to a customer (`CRM.Relation`) and has one or more
  **lines**; each line owns a production route (`OrderRouteStep`) and a bill of
  materials (`OrderLineMaterial`), copied from a `Catalog` product template and
  **snapshotting** its price/cost/margin (via `Pricing.quote/3`) and per-step
  duration/cost (via `Catalog.estimate/2`). Snapshots keep an order independent
  of later price/machine/material changes.

  Progress rolls up: each route step has its own status, a line's status derives
  from its steps, and the order's lifecycle (`draft → confirmed → in_production →
  completed`, plus `cancelled`) is gated on that progress. Completing an order
  consumes the materials' stock through `Inventory.consume/3` (which permits
  negative stock — a material may be specially purchased for the order). Orders
  are cancelled, never deleted.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo
  alias Productionflow.{Catalog, Pricing, Inventory, Production, CRM}

  alias Productionflow.Orders.{
    Order,
    OrderLine,
    OrderRouteStep,
    OrderLineMaterial,
    OrderDelivery,
    OrderDeliveryItem,
    Settings,
    NumberCounter
  }

  ## Settings (singleton)

  @doc "Returns the order settings, creating the singleton row if missing."
  def get_settings do
    Repo.get(Settings, 1) || create_default_settings()
  end

  defp create_default_settings do
    %Settings{id: 1}
    |> Settings.changeset(%{number_mode: :per_year, number_prefix: "ORD"})
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    Repo.get!(Settings, 1)
  end

  @doc "Returns a changeset for the order settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  @doc "Updates the order settings."
  def update_settings(attrs),
    do: get_settings() |> Settings.changeset(attrs) |> Repo.update()

  ## Orders

  @doc """
  Lists orders, most recent first.

  ## Options
    * `:search` - matches order number, reference or customer name
    * `:status` - filter to a single status
  """
  def list_orders(opts \\ []) do
    Order
    |> join(:inner, [o], r in assoc(o, :relation), as: :relation)
    |> filter_order_search(Keyword.get(opts, :search))
    |> filter_order_status(Keyword.get(opts, :status))
    |> order_by([o], desc: o.inserted_at)
    |> preload([relation: r], relation: r)
    |> Repo.all()
  end

  defp filter_order_search(query, search) when search in [nil, ""], do: query

  defp filter_order_search(query, search) do
    like = "%#{String.replace(search, ~r/[%_]/, "")}%"

    where(
      query,
      [o, relation: r],
      ilike(o.number, ^like) or ilike(o.reference, ^like) or ilike(r.name, ^like)
    )
  end

  defp filter_order_status(query, status) when status in [nil, "", :all], do: query
  defp filter_order_status(query, status), do: where(query, [o], o.status == ^status)

  @doc "Gets an order with its customer, lines, route steps, materials and dependencies preloaded."
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([:relation, {:deliveries, deliveries_preload()}, lines: line_preloads()])
  end

  defp line_preloads, do: [:route_steps, :materials, depends_on: :route_steps]

  defp deliveries_preload do
    items = from(i in OrderDeliveryItem, order_by: [asc: i.order_line_id])
    deliveries = from(d in OrderDelivery, order_by: [asc: d.position, asc: d.id])
    {deliveries, [items: items]}
  end

  @doc "Returns a changeset for an order's editable fields."
  def change_order(%Order{} = order, attrs \\ %{}), do: Order.changeset(order, attrs)

  @doc """
  Creates a draft order, generating its number atomically from the configured
  numbering scheme.
  """
  def create_order(attrs) do
    settings = get_settings()
    today = Date.utc_today()

    Repo.transact(fn ->
      number = generate_number(settings, today)

      %Order{number: number, status: :draft, order_date: today}
      |> Order.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc "Updates an order's editable fields (while draft or confirmed)."
  def update_order(%Order{status: status} = order, attrs) when status in [:draft, :confirmed],
    do: order |> Order.changeset(attrs) |> Repo.update()

  def update_order(%Order{}, _attrs), do: {:error, :not_editable}

  ## Numbering

  defp generate_number(%Settings{} = settings, today) do
    {scope, year_part} =
      case settings.number_mode do
        :per_year -> {Integer.to_string(today.year), Integer.to_string(today.year)}
        :continuous -> {"global", nil}
      end

    seq = scope |> next_counter_value() |> Integer.to_string() |> String.pad_leading(4, "0")

    [settings.number_prefix, year_part, seq]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("-")
  end

  # Locks (or creates then locks) the scope's counter row and returns the next
  # value. Must run inside the order-creation transaction.
  defp next_counter_value(scope) do
    counter = lock_counter(scope) || create_and_lock_counter(scope)

    counter
    |> Ecto.Changeset.change(value: counter.value + 1)
    |> Repo.update!()
    |> Map.fetch!(:value)
  end

  defp lock_counter(scope) do
    Repo.one(from c in NumberCounter, where: c.scope == ^scope, lock: "FOR UPDATE")
  end

  defp create_and_lock_counter(scope) do
    %NumberCounter{scope: scope, value: 0}
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :scope)

    lock_counter(scope)
  end

  ## Lines

  @doc "Gets an order line with its route steps, materials and dependencies preloaded."
  def get_line!(id),
    do: OrderLine |> Repo.get!(id) |> Repo.preload(line_preloads())

  @doc """
  Adds a line built from a product template at `quantity`: snapshots the
  customer price/cost/margin and copies the route + bill of materials. Only
  allowed while the order is a draft.
  """
  def add_line_from_template(%Order{status: status} = order, template_id, quantity)
      when status in [:draft, :confirmed] do
    template = Catalog.get_product_template!(template_id)
    order = Repo.preload(order, :relation)
    quote = Pricing.quote(template, quantity, relation: order.relation)

    Repo.transact(fn ->
      line = insert_line_from_quote(order, template, quote)
      copy_route_steps(line, quote.estimate.steps)
      copy_materials(line, quote.estimate.materials)
      line = get_line!(line.id)
      rebalance_line(line, order_deliveries(order.id))
      {:ok, get_line!(line.id)}
    end)
  end

  def add_line_from_template(%Order{}, _template_id, _quantity), do: {:error, :not_editable}

  defp insert_line_from_quote(order, template, quote) do
    %OrderLine{
      order_id: order.id,
      product_template_id: template.id,
      position: next_line_position(order),
      output_unit: template.output_unit,
      unit_price: quote.unit_price,
      total_price: quote.total_price,
      internal_unit_cost: quote.internal_unit_cost,
      internal_total_cost: quote.internal_total_cost,
      unit_margin: quote.unit_margin,
      total_margin: quote.total_margin,
      price_source: quote.price_source
    }
    |> OrderLine.changeset(%{description: template.name, quantity: quote.quantity})
    |> Repo.insert!()
  end

  defp copy_route_steps(line, step_lines) do
    Enum.each(step_lines, fn %{step: step, machine_quantity: machine_qty, estimate: est} ->
      %OrderRouteStep{
        order_line_id: line.id,
        machine_name: step.machine.name,
        position: step.position,
        machine_quantity: machine_qty,
        duration_minutes: est.duration_minutes,
        machine_cost: est.machine_cost,
        labour_cost: est.labour_cost,
        energy_cost: est.energy_cost,
        status: :pending
      }
      |> OrderRouteStep.changeset(%{
        machine_id: step.machine_id,
        quantity_per_unit: step.quantity_per_unit
      })
      |> Repo.insert!()
    end)
  end

  defp copy_materials(line, material_lines) do
    Enum.each(material_lines, fn %{line: bom, consumption: consumption, cost: cost} ->
      %OrderLineMaterial{
        order_line_id: line.id,
        material_name: bom.material.name,
        unit: bom.material.unit,
        unit_cost: bom.material.cost_price,
        cost: cost
      }
      |> OrderLineMaterial.changeset(%{material_id: bom.material_id, quantity: consumption})
      |> Repo.insert!()
    end)
  end

  @doc "Deletes a line (while the order is editable). Its delivery items cascade."
  def delete_line(%OrderLine{} = line) do
    if editable_order?(line.order_id),
      do: Repo.delete(line),
      else: {:error, :not_editable}
  end

  defp next_line_position(order) do
    max =
      from(l in OrderLine, where: l.order_id == ^order.id, select: max(l.position)) |> Repo.one()

    (max || -1) + 1
  end

  defp editable_order?(order_id) do
    Repo.one(from o in Order, where: o.id == ^order_id, select: o.status) in [:draft, :confirmed]
  end

  ## Ad-hoc lines (built from scratch, not from a template)

  @doc "Returns a changeset for an order line's editable fields."
  def change_line(%OrderLine{} = line, attrs \\ %{}), do: OrderLine.changeset(line, attrs)

  @doc """
  Adds a blank, ad-hoc line (no template) to a draft order. A non-blank
  `unit_price` makes the price manual; otherwise it is calculated from the line's
  route + materials cost plus the default margin as those are added.
  """
  def add_blank_line(%Order{status: status} = order, attrs)
      when status in [:draft, :confirmed] do
    manual = parse_decimal(attrs["unit_price"])

    %OrderLine{
      order_id: order.id,
      position: next_line_position(order),
      price_source: if(manual, do: :manual, else: :calculated),
      unit_price: manual
    }
    |> OrderLine.changeset(attrs)
    |> Repo.insert()
    |> recalc_after()
  end

  def add_blank_line(%Order{}, _attrs), do: {:error, :not_editable}

  @doc "Updates an ad-hoc line's fields (description, quantity, output unit, manual price)."
  def update_line(%OrderLine{} = line, attrs) do
    with :ok <- ensure_editable(line) do
      manual = parse_decimal(attrs["unit_price"])

      line
      |> OrderLine.changeset(attrs)
      |> Ecto.Changeset.put_change(:price_source, if(manual, do: :manual, else: :calculated))
      |> Ecto.Changeset.put_change(:unit_price, manual)
      |> Repo.update()
      |> recalc_after()
    end
  end

  ## Ad-hoc route steps

  @doc "Gets an order route step."
  def get_line_route_step!(id), do: Repo.get!(OrderRouteStep, id)

  @doc """
  Adds a route step to an ad-hoc line: the machine plus the total quantity it
  processes (`machine_quantity`), from which time and cost are derived.
  """
  def add_line_route_step(%OrderLine{} = line, attrs) do
    with :ok <- ensure_editable(line) do
      changeset =
        OrderRouteStep.ad_hoc_changeset(
          %OrderRouteStep{order_line_id: line.id, position: next_step_position(line)},
          attrs
        )

      if changeset.valid? do
        changeset
        |> apply_step_estimate()
        |> Repo.insert()
        |> recalc_line_after(line)
      else
        {:error, %{changeset | action: :insert}}
      end
    end
  end

  @doc "Deletes a route step from an ad-hoc line."
  def delete_line_route_step(%OrderRouteStep{} = step) do
    line = get_line!(step.order_line_id)

    with :ok <- ensure_editable(line) do
      Repo.delete(step)
      {:ok, recalculate_line!(get_line!(line.id))}
    end
  end

  # Fills a valid ad-hoc step changeset with the machine name + time/cost snapshot.
  defp apply_step_estimate(changeset) do
    machine = Production.get_machine!(Ecto.Changeset.get_field(changeset, :machine_id))
    quantity = Ecto.Changeset.get_field(changeset, :machine_quantity)
    est = Production.estimate(machine, quantity, [])

    changeset
    |> Ecto.Changeset.put_change(:machine_name, machine.name)
    |> Ecto.Changeset.put_change(:quantity_per_unit, Decimal.new(1))
    |> Ecto.Changeset.put_change(:duration_minutes, est.duration_minutes)
    |> Ecto.Changeset.put_change(:machine_cost, est.machine_cost)
    |> Ecto.Changeset.put_change(:labour_cost, est.labour_cost)
    |> Ecto.Changeset.put_change(:energy_cost, est.energy_cost)
  end

  defp next_step_position(line) do
    max =
      from(s in OrderRouteStep, where: s.order_line_id == ^line.id, select: max(s.position))
      |> Repo.one()

    (max || -1) + 1
  end

  ## Ad-hoc materials

  @doc "Gets an order line material."
  def get_line_material!(id), do: Repo.get!(OrderLineMaterial, id)

  @doc "Adds a material (with a total consumption quantity) to an ad-hoc line."
  def add_line_material(%OrderLine{} = line, attrs) do
    with :ok <- ensure_editable(line) do
      changeset = OrderLineMaterial.changeset(%OrderLineMaterial{order_line_id: line.id}, attrs)

      if changeset.valid? do
        changeset
        |> apply_material_snapshot()
        |> Repo.insert()
        |> recalc_line_after(line)
      else
        {:error, %{changeset | action: :insert}}
      end
    end
  end

  @doc "Deletes a material from an ad-hoc line."
  def delete_line_material(%OrderLineMaterial{} = line_material) do
    line = get_line!(line_material.order_line_id)

    with :ok <- ensure_editable(line) do
      Repo.delete(line_material)
      {:ok, recalculate_line!(get_line!(line.id))}
    end
  end

  defp apply_material_snapshot(changeset) do
    material = Inventory.get_material!(Ecto.Changeset.get_field(changeset, :material_id))
    quantity = Ecto.Changeset.get_field(changeset, :quantity)

    changeset
    |> Ecto.Changeset.put_change(:material_name, material.name)
    |> Ecto.Changeset.put_change(:unit, material.unit)
    |> Ecto.Changeset.put_change(:unit_cost, material.cost_price)
    |> Ecto.Changeset.put_change(:cost, Decimal.mult(quantity, material.cost_price))
  end

  # A line is editable (route/materials) only while ad-hoc and the order is draft.
  defp ensure_editable(%OrderLine{} = line) do
    cond do
      not OrderLine.ad_hoc?(line) -> {:error, :not_ad_hoc}
      not editable_order?(line.order_id) -> {:error, :not_editable}
      true -> :ok
    end
  end

  ## Line cost/price recomputation

  @doc """
  Recomputes a line's cost (from its route steps + materials) and, unless its
  price is manual, its calculated price from the default margin. Returns the
  reloaded line.
  """
  def recalculate_line!(%OrderLine{} = line) do
    margin = Pricing.get_settings().default_margin_pct
    machine = sum_machine_cost(line.route_steps)
    labour = sum_decimal(line.route_steps, & &1.labour_cost)
    energy = sum_decimal(line.route_steps, & &1.energy_cost)
    material = sum_decimal(line.materials, & &1.cost)

    total_cost =
      if machine,
        do: machine |> Decimal.add(labour) |> Decimal.add(energy) |> Decimal.add(material)

    unit_cost = unit_div(total_cost, line.quantity)
    {unit_price, total_price} = line_price(line, unit_cost, margin)
    {unit_margin, total_margin} = line_margins(unit_price, unit_cost, total_price, total_cost)

    line
    |> Ecto.Changeset.change(
      internal_unit_cost: unit_cost,
      internal_total_cost: total_cost,
      unit_price: unit_price,
      total_price: total_price,
      unit_margin: unit_margin,
      total_margin: total_margin
    )
    |> Repo.update!()

    get_line!(line.id)
  end

  defp line_price(%OrderLine{price_source: :manual} = line, _unit_cost, _margin),
    do: {line.unit_price, mult_or_nil(line.unit_price, line.quantity)}

  defp line_price(%OrderLine{} = line, unit_cost, margin) do
    unit_price = Pricing.default_unit_price(unit_cost, margin)
    {unit_price, mult_or_nil(unit_price, line.quantity)}
  end

  defp line_margins(unit_price, unit_cost, _total_price, _total_cost)
       when is_nil(unit_price) or is_nil(unit_cost),
       do: {nil, nil}

  defp line_margins(unit_price, unit_cost, total_price, total_cost),
    do: {Decimal.sub(unit_price, unit_cost), Decimal.sub(total_price, total_cost)}

  defp sum_machine_cost(steps) do
    Enum.reduce_while(steps, Decimal.new(0), fn step, acc ->
      case step.machine_cost do
        nil -> {:halt, nil}
        cost -> {:cont, Decimal.add(acc, cost)}
      end
    end)
  end

  defp sum_decimal(rows, fun) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      Decimal.add(acc, fun.(row) || Decimal.new(0))
    end)
  end

  defp unit_div(nil, _qty), do: nil

  defp unit_div(total, qty) do
    if Decimal.compare(qty, 0) == :gt, do: Decimal.div(total, qty), else: nil
  end

  defp mult_or_nil(nil, _qty), do: nil
  defp mult_or_nil(_price, nil), do: nil
  defp mult_or_nil(price, qty), do: Decimal.mult(price, qty)

  ## Dependencies

  @doc """
  Replaces a line's dependencies with the given line ids (same order only; self
  and blanks ignored). Only while the order is editable.
  """
  def set_line_dependencies(%OrderLine{} = line, depends_on_ids) do
    if editable_order?(line.order_id) do
      ids =
        depends_on_ids
        |> List.wrap()
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(&to_int/1)
        |> Enum.reject(&(&1 == line.id))

      deps = Repo.all(from l in OrderLine, where: l.id in ^ids and l.order_id == ^line.order_id)

      line
      |> Repo.preload(:depends_on)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:depends_on, deps)
      |> Repo.update()
    else
      {:error, :not_editable}
    end
  end

  ## Deliveries

  @doc "Lists an order's deliveries, in order."
  def order_deliveries(order_id) do
    Repo.all(
      from d in OrderDelivery,
        where: d.order_id == ^order_id,
        order_by: [asc: d.position, asc: d.id]
    )
  end

  @doc "Gets a delivery."
  def get_delivery!(id), do: Repo.get!(OrderDelivery, id)

  @doc "Gets a delivery item (a line's allocation to a delivery)."
  def get_delivery_item!(id), do: Repo.get!(OrderDeliveryItem, id)

  @doc """
  Adds a delivery destination to an editable order. The address comes from a
  chosen customer address (`address_id`) or one-off fields; a one-off can also be
  saved onto the customer (`save_to_customer`). Lines are then auto-divided
  equally across all deliveries.
  """
  def add_delivery(%Order{} = order, attrs) do
    if editable_order?(order.id) do
      order = Repo.preload(order, :relation)

      Repo.transact(fn ->
        with {:ok, snapshot} <- resolve_delivery_attrs(order, attrs),
             {:ok, delivery} <-
               %OrderDelivery{order_id: order.id, position: next_delivery_position(order.id)}
               |> OrderDelivery.changeset(snapshot)
               |> Repo.insert() do
          rebalance_all_lines(order.id)
          {:ok, delivery}
        end
      end)
    else
      {:error, :not_editable}
    end
  end

  @doc "Removes a delivery and re-divides the lines across the remaining ones."
  def delete_delivery(%OrderDelivery{} = delivery) do
    if editable_order?(delivery.order_id) do
      Repo.delete(delivery)
      rebalance_all_lines(delivery.order_id)
      {:ok, delivery}
    else
      {:error, :not_editable}
    end
  end

  @doc "Sets a single allocation quantity manually (persists until the next rebalance)."
  def update_delivery_item(%OrderDeliveryItem{} = item, quantity) do
    if editable_order?(order_id_for_item(item)) do
      item |> OrderDeliveryItem.changeset(%{"quantity" => quantity}) |> Repo.update()
    else
      {:error, :not_editable}
    end
  end

  # Resolves the address into delivery attrs, optionally saving a one-off onto the
  # customer.
  defp resolve_delivery_attrs(order, attrs) do
    case blank_to_nil(attrs["address_id"]) do
      nil ->
        resolve_one_off(order, attrs)

      address_id ->
        address = CRM.get_address!(address_id)

        {:ok,
         %{
           "address_id" => address.id,
           "street" => address.street,
           "postal_code" => address.postal_code,
           "city" => address.city,
           "country" => address.country,
           "planned_date" => attrs["planned_date"]
         }}
    end
  end

  defp resolve_one_off(order, attrs) do
    base = Map.take(attrs, ["street", "postal_code", "city", "country", "planned_date"])

    if truthy(attrs["save_to_customer"]) do
      case CRM.create_address(order.relation, %{
             kind: :delivery,
             street: attrs["street"],
             postal_code: attrs["postal_code"],
             city: attrs["city"],
             country: attrs["country"]
           }) do
        {:ok, address} -> {:ok, Map.put(base, "address_id", address.id)}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:ok, base}
    end
  end

  defp next_delivery_position(order_id) do
    max =
      from(d in OrderDelivery, where: d.order_id == ^order_id, select: max(d.position))
      |> Repo.one()

    (max || -1) + 1
  end

  defp order_id_for_item(item) do
    Repo.one(
      from d in OrderDelivery,
        join: i in OrderDeliveryItem,
        on: i.order_delivery_id == d.id,
        where: i.id == ^item.id,
        select: d.order_id
    )
  end

  # Re-divides every line of the order equally across its deliveries.
  defp rebalance_all_lines(order_id) do
    deliveries = order_deliveries(order_id)
    lines = Repo.all(from l in OrderLine, where: l.order_id == ^order_id)
    Enum.each(lines, &rebalance_line(&1, deliveries))
  end

  # Replaces a line's allocations with a split across `deliveries`. Items are not
  # divisible, so each part is a whole number: any whole remainder is spread one
  # extra per delivery across the first few; only a genuinely fractional quantity
  # (e.g. m²) leaves a fractional rest, placed on the first delivery. The parts
  # always sum exactly to the line quantity.
  defp rebalance_line(_line, []), do: :ok

  defp rebalance_line(line, deliveries) do
    Repo.delete_all(from i in OrderDeliveryItem, where: i.order_line_id == ^line.id)

    deliveries
    |> Enum.zip(whole_division(line.quantity, length(deliveries)))
    |> Enum.each(fn {delivery, amount} ->
      Repo.insert!(%OrderDeliveryItem{
        order_delivery_id: delivery.id,
        order_line_id: line.id,
        quantity: amount
      })
    end)
  end

  defp whole_division(qty, n) do
    base = qty |> Decimal.div(n) |> Decimal.round(0, :down)
    remainder = Decimal.sub(qty, Decimal.mult(base, n))
    whole_remainder = Decimal.round(remainder, 0, :down)
    frac = Decimal.sub(remainder, whole_remainder)
    extra = Decimal.to_integer(whole_remainder)

    for i <- 0..(n - 1) do
      amount = if i < extra, do: Decimal.add(base, 1), else: base
      if i == 0 and Decimal.compare(frac, 0) == :gt, do: Decimal.add(amount, frac), else: amount
    end
  end

  ## Shared helpers

  defp recalc_after({:ok, line}) do
    line = recalculate_line!(get_line!(line.id))
    rebalance_line(line, order_deliveries(line.order_id))
    {:ok, get_line!(line.id)}
  end

  defp recalc_after(error), do: error

  defp recalc_line_after({:ok, _child}, line),
    do: {:ok, recalculate_line!(get_line!(line.id))}

  defp recalc_line_after(error, _line), do: error

  defp parse_decimal(value) when value in [nil, ""], do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  defp parse_decimal(%Decimal{} = value), do: value

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp truthy(value), do: value in [true, "true", "on"]

  ## Lifecycle

  @doc "Moves an order to `new_status` (for confirmed / in_production / cancelled)."
  def transition_order(%Order{} = order, new_status),
    do: order |> Order.transition_changeset(new_status) |> Repo.update()

  @doc "Cancels an order (allowed from any non-terminal status)."
  def cancel_order(%Order{} = order), do: transition_order(order, :cancelled)

  @doc """
  Completes an order: requires it to be in production with every route step done,
  consumes each line's materials (booking stock movements, negative allowed), and
  records when each material was consumed. Runs atomically.
  """
  def complete_order(%Order{} = order, user) do
    order = Repo.preload(order, lines: [materials: :material])

    Repo.transact(fn ->
      cond do
        order.status != :in_production -> {:error, :not_in_production}
        not all_steps_done?(order.id) -> {:error, :steps_unfinished}
        true -> do_complete(order, user)
      end
    end)
  end

  defp do_complete(order, user) do
    now = DateTime.utc_now(:second)

    for line <- order.lines, material <- line.materials do
      {:ok, _} =
        Inventory.consume(material.material, user, %{
          quantity: material.quantity,
          note: "Order #{order.number}"
        })

      material |> Ecto.Changeset.change(consumed_at: now) |> Repo.update!()
    end

    Order.transition_changeset(order, :completed) |> Repo.update()
  end

  ## Route steps

  @doc "Gets an order route step."
  def get_route_step!(id), do: Repo.get!(OrderRouteStep, id)

  @doc """
  Advances a route step to `new_status`. Only allowed while the owning order is
  in production, the line is not blocked by an unfinished dependency, and the
  step transition is legal.
  """
  def advance_step(%OrderRouteStep{} = step, new_status) do
    line = get_line!(step.order_line_id)

    cond do
      order_status_for_step(step) != :in_production ->
        {:error, :order_not_in_production}

      new_status == :in_progress and blocked?(line) ->
        {:error, :line_blocked}

      true ->
        step |> OrderRouteStep.transition_changeset(new_status) |> Repo.update()
    end
  end

  defp order_status_for_step(step) do
    Repo.one(
      from s in OrderRouteStep,
        join: l in OrderLine,
        on: l.id == s.order_line_id,
        join: o in Order,
        on: o.id == l.order_id,
        where: s.id == ^step.id,
        select: o.status
    )
  end

  ## Derived progress

  @doc """
  The derived production status of a line: `:blocked` when a dependency line
  isn't done yet, otherwise from its route steps — `:done` when all steps are
  done, `:in_progress` when any has started, else `:pending`.
  """
  def line_status(%OrderLine{} = line) do
    if blocked?(line), do: :blocked, else: status_from_steps(line.route_steps)
  end

  defp status_from_steps(steps) when is_list(steps) do
    cond do
      steps != [] and Enum.all?(steps, &(&1.status == :done)) -> :done
      Enum.any?(steps, &(&1.status in [:in_progress, :done])) -> :in_progress
      true -> :pending
    end
  end

  # A line is blocked while any line it depends on is not fully done. When
  # `depends_on` isn't loaded, treat as not blocked.
  defp blocked?(%OrderLine{depends_on: deps}) when is_list(deps),
    do: Enum.any?(deps, &(status_from_steps(&1.route_steps) != :done))

  defp blocked?(_line), do: false

  @doc "True when the order has no unfinished route steps."
  def all_steps_done?(order_id) do
    count =
      from(s in OrderRouteStep,
        join: l in OrderLine,
        on: l.id == s.order_line_id,
        where: l.order_id == ^order_id and s.status != :done,
        select: count(s.id)
      )
      |> Repo.one()

    count == 0
  end

  @doc "Order totals summed from the line snapshots (price, cost, margin)."
  def order_totals(%Order{lines: lines}) when is_list(lines) do
    price = sum_lines(lines, & &1.total_price)
    cost = sum_lines(lines, & &1.internal_total_cost)
    %{price: price, cost: cost, margin: Decimal.sub(price, cost)}
  end

  defp sum_lines(lines, fun) do
    Enum.reduce(lines, Decimal.new(0), fn line, acc ->
      Decimal.add(acc, fun.(line) || Decimal.new(0))
    end)
  end
end
