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
  alias Productionflow.{Catalog, Pricing, Inventory}

  alias Productionflow.Orders.{
    Order,
    OrderLine,
    OrderRouteStep,
    OrderLineMaterial,
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

  @doc "Gets an order with its customer, lines, route steps and materials preloaded."
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([:relation, lines: [:route_steps, :materials]])
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

  @doc "Updates an order's editable fields (only while it is still a draft)."
  def update_order(%Order{status: :draft} = order, attrs),
    do: order |> Order.changeset(attrs) |> Repo.update()

  def update_order(%Order{}, _attrs), do: {:error, :not_draft}

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

  @doc "Gets an order line with its route steps and materials preloaded."
  def get_line!(id),
    do: OrderLine |> Repo.get!(id) |> Repo.preload([:route_steps, :materials])

  @doc """
  Adds a line built from a product template at `quantity`: snapshots the
  customer price/cost/margin and copies the route + bill of materials. Only
  allowed while the order is a draft.
  """
  def add_line_from_template(%Order{status: :draft} = order, template_id, quantity) do
    template = Catalog.get_product_template!(template_id)
    order = Repo.preload(order, :relation)
    quote = Pricing.quote(template, quantity, relation: order.relation)

    Repo.transact(fn ->
      line = insert_line_from_quote(order, template, quote)
      copy_route_steps(line, quote.estimate.steps)
      copy_materials(line, quote.estimate.materials)
      {:ok, get_line!(line.id)}
    end)
  end

  def add_line_from_template(%Order{}, _template_id, _quantity), do: {:error, :not_draft}

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

  @doc "Deletes a line (only while the order is a draft)."
  def delete_line(%OrderLine{} = line) do
    if draft_order?(line.order_id),
      do: Repo.delete(line),
      else: {:error, :not_draft}
  end

  defp next_line_position(order) do
    max =
      from(l in OrderLine, where: l.order_id == ^order.id, select: max(l.position)) |> Repo.one()

    (max || -1) + 1
  end

  defp draft_order?(order_id) do
    Repo.one(from o in Order, where: o.id == ^order_id, select: o.status) == :draft
  end

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
  in production, and only for legal step transitions.
  """
  def advance_step(%OrderRouteStep{} = step, new_status) do
    if order_status_for_step(step) == :in_production do
      step |> OrderRouteStep.transition_changeset(new_status) |> Repo.update()
    else
      {:error, :order_not_in_production}
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
  The derived production status of a line from its route steps: `:done` when all
  steps are done, `:in_progress` when any step has started, otherwise `:pending`.
  """
  def line_status(%OrderLine{route_steps: steps}) when is_list(steps) do
    cond do
      steps != [] and Enum.all?(steps, &(&1.status == :done)) -> :done
      Enum.any?(steps, &(&1.status in [:in_progress, :done])) -> :in_progress
      true -> :pending
    end
  end

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
