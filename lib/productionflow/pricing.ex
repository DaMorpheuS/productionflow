defmodule Productionflow.Pricing do
  @moduledoc """
  The Pricing context: turns the internal cost of a product template
  (`Productionflow.Catalog.estimate/2`) into a customer-facing price.

  Two layers stack on top of cost:

    * a **default margin** (markup on cost) — a global default in the singleton
      settings, optionally overridden per product template (`margin_pct`);
    * **price lists** of graduated, per-unit tiers (`PriceListItem`), optionally
      bound to a CRM relation for customer-specific pricing.

  `quote/3` composes both into a non-persisted `Productionflow.Pricing.Quote`
  that keeps the internal cost and the resulting margin visible — including when
  a chosen price sits below cost. Price resolution: a relation-bound item beats a
  general one; within the winning scope the highest tier with
  `min_quantity ≤ qty` wins. All math is `Decimal`, rounded only at display.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo
  alias Productionflow.Catalog
  alias Productionflow.Catalog.ProductTemplate
  alias Productionflow.Pricing.{Settings, PriceList, PriceListItem, Quote}

  ## Settings (singleton)

  @doc "Returns the pricing settings, creating the singleton row if missing."
  def get_settings do
    Repo.get(Settings, 1) || create_default_settings()
  end

  defp create_default_settings do
    %Settings{id: 1}
    |> Settings.changeset(%{default_margin_pct: Decimal.new(0)})
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    Repo.get!(Settings, 1)
  end

  @doc "Returns a changeset for the settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc "Updates the pricing settings."
  def update_settings(attrs) do
    get_settings()
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  ## Price lists (automatic scope buckets)

  # Price lists aren't named, user-managed containers. Each is a scope bucket —
  # one general list (no relation) plus one per customer — created on demand when
  # the first tier for that scope is added from a product. `get_or_create` keeps
  # the per-scope singleton; tiers are managed per product via the functions
  # below.

  @doc """
  Finds (or creates) the price-list bucket for a scope. `relation_id` of `nil`
  (or `""`) is the general bucket; any other value is that customer's bucket.
  """
  def get_or_create_price_list(relation_id) do
    relation_id = normalize_id(relation_id)

    case scope_bucket(relation_id) do
      nil ->
        {:ok, list} =
          %PriceList{} |> PriceList.changeset(%{relation_id: relation_id}) |> Repo.insert()

        list

      list ->
        list
    end
  end

  defp scope_bucket(nil),
    do: Repo.one(from l in PriceList, where: is_nil(l.relation_id), limit: 1)

  defp scope_bucket(id), do: Repo.get_by(PriceList, relation_id: id)

  @doc "Lists the price tiers defined for a product across all scopes, general first."
  def template_price_tiers(%ProductTemplate{} = template) do
    from(i in PriceListItem,
      join: l in assoc(i, :price_list),
      where: i.product_template_id == ^template.id,
      order_by: [asc_nulls_first: l.relation_id, asc: i.min_quantity],
      preload: [price_list: :relation]
    )
    |> Repo.all()
  end

  @doc """
  Adds a price tier for a product. `attrs` carry the chosen scope as
  `scope_relation_id` (blank/nil = general); the matching bucket is resolved or
  created. Returns `{:ok, item}` or `{:error, changeset}`.
  """
  def add_template_price_tier(%ProductTemplate{} = template, attrs) do
    changeset =
      %PriceListItem{}
      |> PriceListItem.changeset(Map.put(attrs, "product_template_id", template.id))

    if changeset.valid? do
      list = get_or_create_price_list(Ecto.Changeset.get_field(changeset, :scope_relation_id))

      changeset
      |> Ecto.Changeset.put_change(:price_list_id, list.id)
      |> Repo.insert()
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  ## Price list items

  @doc "Gets a price list item."
  def get_price_list_item!(id), do: Repo.get!(PriceListItem, id)

  @doc "Returns a changeset for a price list item."
  def change_price_list_item(%PriceListItem{} = item, attrs \\ %{}),
    do: PriceListItem.changeset(item, attrs)

  @doc "Deletes a price list item."
  def delete_price_list_item(%PriceListItem{} = item), do: Repo.delete(item)

  ## Pricing

  @doc """
  The effective default margin for a template: its own `margin_pct` when set,
  otherwise the global `default_margin_pct` from settings.
  """
  def margin_pct(template, %Settings{} = settings) do
    template.margin_pct || settings.default_margin_pct
  end

  @doc """
  The default sales price per unit: `unit_cost × (1 + margin/100)`.
  Returns `nil` when `unit_cost` is `nil` (incomplete machine cost basis).
  """
  def default_unit_price(nil, _margin_pct), do: nil

  def default_unit_price(unit_cost, margin_pct) do
    Decimal.mult(unit_cost, Decimal.add(Decimal.new(1), Decimal.div(dec(margin_pct), 100)))
  end

  @doc """
  Resolves the best-matching price-list item for a template at `quantity`,
  optionally scoped to a `relation`. A relation-bound item wins over a general
  one; within the winning scope the highest tier with `min_quantity ≤ qty` wins
  (ties broken by lowest id). Returns `nil` when nothing matches.
  """
  def resolve_item(template, quantity, relation \\ nil) do
    qty = dec(quantity)

    candidates =
      from(i in PriceListItem,
        join: l in assoc(i, :price_list),
        where: i.product_template_id == ^template.id and i.min_quantity <= ^qty,
        select: %{item: i, relation_id: l.relation_id}
      )
      |> Repo.all()

    scoped =
      case relation do
        nil -> Enum.filter(candidates, &is_nil(&1.relation_id))
        %{id: rid} -> prefer_relation(candidates, rid)
      end

    scoped
    |> Enum.map(& &1.item)
    |> Enum.max_by(&{Decimal.to_float(&1.min_quantity), -&1.id}, fn -> nil end)
  end

  # Relation-bound items win when present; otherwise fall back to general items.
  defp prefer_relation(candidates, relation_id) do
    case Enum.filter(candidates, &(&1.relation_id == relation_id)) do
      [] -> Enum.filter(candidates, &is_nil(&1.relation_id))
      bound -> bound
    end
  end

  @doc """
  Prices `quantity` units of a product template, returning a
  `Productionflow.Pricing.Quote`. Pass `relation: %CRM.Relation{}` to apply
  customer-specific price lists.
  """
  def quote(template, quantity, opts \\ []) do
    qty = dec(quantity)
    relation = Keyword.get(opts, :relation)
    settings = get_settings()
    estimate = Catalog.estimate(template, qty)
    margin = margin_pct(template, settings)

    unit_cost = estimate.unit_cost
    default_unit = default_unit_price(unit_cost, margin)
    item = resolve_item(template, qty, relation)
    {source, unit_price} = resolve_unit_price(item, default_unit)
    total_price = mult_or_nil(unit_price, qty)

    {unit_margin, total_margin, margin_pct_of_price, below_cost?} =
      margins(unit_price, unit_cost, total_price, estimate.total_cost)

    %Quote{
      template: template,
      quantity: qty,
      relation: relation,
      estimate: estimate,
      internal_unit_cost: unit_cost,
      internal_total_cost: estimate.total_cost,
      effective_margin_pct: dec(margin),
      default_unit_price: default_unit,
      price_source: source,
      price_list_item: item,
      unit_price: unit_price,
      total_price: total_price,
      unit_margin: unit_margin,
      total_margin: total_margin,
      margin_pct_of_price: margin_pct_of_price,
      below_cost?: below_cost?
    }
  end

  defp resolve_unit_price(nil, default_unit), do: {:calculated, default_unit}

  defp resolve_unit_price(%PriceListItem{kind: :fixed_price, unit_price: price}, _default),
    do: {:price_list, price}

  defp resolve_unit_price(%PriceListItem{kind: :discount_percent, discount_pct: pct}, default) do
    {:price_list, discounted(default, pct)}
  end

  defp discounted(nil, _pct), do: nil

  defp discounted(default_unit, pct) do
    Decimal.mult(default_unit, Decimal.sub(Decimal.new(1), Decimal.div(dec(pct), 100)))
  end

  # Margin is only meaningful when both a price and an internal cost are known.
  defp margins(unit_price, unit_cost, _total_price, _total_cost)
       when is_nil(unit_price) or is_nil(unit_cost),
       do: {nil, nil, nil, false}

  defp margins(unit_price, unit_cost, total_price, total_cost) do
    unit_margin = Decimal.sub(unit_price, unit_cost)
    total_margin = Decimal.sub(total_price, total_cost)

    pct_of_price =
      if Decimal.compare(unit_price, 0) == :gt do
        unit_margin |> Decimal.div(unit_price) |> Decimal.mult(100)
      end

    {unit_margin, total_margin, pct_of_price, Decimal.compare(unit_margin, 0) == :lt}
  end

  defp mult_or_nil(nil, _qty), do: nil
  defp mult_or_nil(price, qty), do: Decimal.mult(price, qty)

  defp normalize_id(id) when id in [nil, ""], do: nil
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
  defp normalize_id(id) when is_integer(id), do: id

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
