defmodule Productionflow.Catalog do
  @moduledoc """
  The Catalog context: product templates that are reusable production recipes —
  an ordered production route (steps on machines) plus a bill of materials.

  `estimate/2` composes the per-machine time/cost engine (`Production.estimate/3`)
  across the route and adds material consumption to produce an internal cost &
  time breakdown for a quantity. Customer pricing (margin, price lists) is a
  separate concern handled by `Productionflow.Pricing` (M5b). All math is
  `Decimal`, computed on the fly and rounded only at display.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo
  alias Productionflow.Production
  alias Productionflow.Catalog.{ProductTemplate, RouteStep, TemplateMaterial, CostEstimate}

  ## Product templates

  @doc """
  Lists product templates ordered by name.

  ## Options
    * `:search` - case-insensitive match on name or sku
    * `:include_archived` - when true, also returns archived templates
  """
  def list_product_templates(opts \\ []) do
    ProductTemplate
    |> filter_archived(Keyword.get(opts, :include_archived, false))
    |> filter_search(Keyword.get(opts, :search))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp filter_archived(query, true), do: query
  defp filter_archived(query, _), do: where(query, [t], is_nil(t.archived_at))

  defp filter_search(query, search) when search in [nil, ""], do: query

  defp filter_search(query, search) do
    like = "%#{String.replace(search, ~r/[%_]/, "")}%"
    where(query, [t], ilike(t.name, ^like) or ilike(t.sku, ^like))
  end

  @doc "Gets a template with its route (machines + operators + modifiers) and BoM preloaded."
  def get_product_template!(id) do
    steps = from(s in RouteStep, order_by: [asc: s.position, asc: s.id])

    ProductTemplate
    |> Repo.get!(id)
    |> Repo.preload([
      {:route_steps, {steps, [machine: [:operators, :time_modifiers]]}},
      materials: :material
    ])
  end

  @doc "Returns a changeset for a product template."
  def change_product_template(%ProductTemplate{} = template, attrs \\ %{}),
    do: ProductTemplate.changeset(template, attrs)

  @doc "Creates a product template."
  def create_product_template(attrs),
    do: %ProductTemplate{} |> ProductTemplate.changeset(attrs) |> Repo.insert()

  @doc "Updates a product template."
  def update_product_template(%ProductTemplate{} = template, attrs),
    do: template |> ProductTemplate.changeset(attrs) |> Repo.update()

  @doc "Archives a product template."
  def archive_product_template(%ProductTemplate{} = template),
    do: template |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update()

  @doc "Restores an archived product template."
  def unarchive_product_template(%ProductTemplate{} = template),
    do: template |> Ecto.Changeset.change(archived_at: nil) |> Repo.update()

  @doc "Hard-deletes a product template and its route/BoM (cascade)."
  def delete_product_template(%ProductTemplate{} = template), do: Repo.delete(template)

  ## Route steps

  @doc "Gets a route step."
  def get_route_step!(id), do: Repo.get!(RouteStep, id)

  @doc "Returns a changeset for a route step."
  def change_route_step(%RouteStep{} = step, attrs \\ %{}), do: RouteStep.changeset(step, attrs)

  @doc "Adds a route step to a template (appended after the last position)."
  def add_route_step(%ProductTemplate{} = template, attrs) do
    %RouteStep{product_template_id: template.id, position: next_step_position(template)}
    |> RouteStep.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a route step."
  def update_route_step(%RouteStep{} = step, attrs),
    do: step |> RouteStep.changeset(attrs) |> Repo.update()

  @doc "Deletes a route step."
  def delete_route_step(%RouteStep{} = step), do: Repo.delete(step)

  defp next_step_position(template) do
    max =
      from(s in RouteStep, where: s.product_template_id == ^template.id, select: max(s.position))
      |> Repo.one()

    (max || -1) + 1
  end

  ## Bill of materials

  @doc "Gets a template material line."
  def get_template_material!(id), do: Repo.get!(TemplateMaterial, id)

  @doc "Returns a changeset for a template material line."
  def change_template_material(%TemplateMaterial{} = line, attrs \\ %{}),
    do: TemplateMaterial.changeset(line, attrs)

  @doc "Adds a material line to a template."
  def add_template_material(%ProductTemplate{} = template, attrs) do
    %TemplateMaterial{product_template_id: template.id}
    |> TemplateMaterial.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a template material line."
  def update_template_material(%TemplateMaterial{} = line, attrs),
    do: line |> TemplateMaterial.changeset(attrs) |> Repo.update()

  @doc "Deletes a template material line."
  def delete_template_material(%TemplateMaterial{} = line), do: Repo.delete(line)

  ## Cost & time estimate

  @doc """
  Estimates duration and internal cost for producing `quantity` units of a
  product template. Returns a `Productionflow.Catalog.CostEstimate`.

  Each route step's machine processes `quantity × step.quantity_per_unit` units;
  each material consumes `quantity × qty_per_unit × (1 + waste_pct/100)`.
  `machine_cost`/`total_cost`/`unit_cost` are `nil` when any step's machine has
  an incomplete cost basis.
  """
  def estimate(%ProductTemplate{} = template, quantity) do
    qty = dec(quantity)

    step_lines =
      Enum.map(template.route_steps, fn step ->
        machine_qty = Decimal.mult(qty, dec(step.quantity_per_unit))

        %{
          step: step,
          machine_quantity: machine_qty,
          estimate: Production.estimate(step.machine, machine_qty, step.time_modifier_ids)
        }
      end)

    material_lines =
      Enum.map(template.materials, fn line ->
        consumption =
          qty
          |> Decimal.mult(dec(line.quantity_per_unit))
          |> Decimal.mult(waste_multiplier(line.waste_pct))

        %{
          line: line,
          consumption: consumption,
          cost: Decimal.mult(consumption, dec(line.material.cost_price))
        }
      end)

    duration = sum_by(step_lines, & &1.estimate.duration_minutes)
    labour = sum_by(step_lines, & &1.estimate.labour_cost)
    energy = sum_by(step_lines, & &1.estimate.energy_cost)
    material_cost = sum_by(material_lines, & &1.cost)
    machine_cost = sum_machine_cost(step_lines)

    total_cost =
      if machine_cost do
        machine_cost |> Decimal.add(labour) |> Decimal.add(energy) |> Decimal.add(material_cost)
      end

    %CostEstimate{
      duration_minutes: duration,
      machine_cost: machine_cost,
      labour_cost: labour,
      energy_cost: energy,
      material_cost: material_cost,
      total_cost: total_cost,
      unit_cost: unit_cost(total_cost, qty),
      steps: step_lines,
      materials: material_lines
    }
  end

  defp waste_multiplier(waste_pct) do
    Decimal.add(Decimal.new(1), Decimal.div(dec(waste_pct), Decimal.new(100)))
  end

  defp sum_by(lines, fun) do
    Enum.reduce(lines, Decimal.new(0), fn line, acc -> Decimal.add(acc, fun.(line)) end)
  end

  # nil-poisoning: if any step has no machine cost (incomplete basis), the whole
  # machine cost is undefined.
  defp sum_machine_cost(step_lines) do
    Enum.reduce_while(step_lines, Decimal.new(0), fn line, acc ->
      case line.estimate.machine_cost do
        nil -> {:halt, nil}
        cost -> {:cont, Decimal.add(acc, cost)}
      end
    end)
  end

  defp unit_cost(nil, _qty), do: nil

  defp unit_cost(total, qty) do
    if Decimal.compare(qty, 0) == :gt, do: Decimal.div(total, qty), else: nil
  end

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
